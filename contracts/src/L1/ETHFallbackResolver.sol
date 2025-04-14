// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {GatewayFetcher} from "@unruggable/gateways/contracts/GatewayFetcher.sol";
import {GatewayRequest, EvalFlag} from "@unruggable/gateways/contracts/GatewayRequest.sol";
import {GatewayFetchTarget, IGatewayVerifier} from "@unruggable/gateways/contracts/GatewayFetchTarget.sol";
import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";
import {IAddrResolver} from "@ens/contracts/resolvers/profiles/IAddrResolver.sol";
import {IAddressResolver} from "@ens/contracts/resolvers/profiles/IAddressResolver.sol";
import {ITextResolver} from "@ens/contracts/resolvers/profiles/ITextResolver.sol";
import {IContentHashResolver} from "@ens/contracts/resolvers/profiles/IContentHashResolver.sol";
import {INameResolver} from "@ens/contracts/resolvers/profiles/INameResolver.sol";
import {IMulticallable} from "@ens/contracts/resolvers/IMulticallable.sol";
import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";
import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {CCIPReader} from "@ens/contracts/ccipRead/CCIPReader.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";

contract ETHFallbackResolver is IExtendedResolver, GatewayFetchTarget, CCIPReader, Ownable, ERC165 {
    using GatewayFetcher for GatewayRequest;

    IBaseRegistrar public immutable ethRegistrarV1;
    IUniversalResolver public immutable universalResolverV1;
    address public immutable burnAddressV1;
    IGatewayVerifier public namechainVerifier;
    address public immutable namechainDatastore;
    address public immutable namechainEthRegistry;

    /// @dev Storage layout of RegistryDatastore.
    uint256 constant SLOT_RD_ENTRIES = 0;

    /// @dev Storage layout of OwnedResolver.
    uint256 constant SLOT_PR_VERSIONS = 0;
    uint256 constant SLOT_PR_ADDRESSES = 2;
    uint256 constant SLOT_PR_CONTENTHASHES = 3;
    uint256 constant SLOT_PR_NAMES = 8;
    uint256 constant SLOT_PR_TEXTS = 10;

    uint8 constant EXIT_CODE_NO_RESOLVER = 2;

    /// @dev Error when `name` does not exist.
    ///      Error selector: `0x5fe9a5df`
    /// @param name The DNS-encoded ENS name.
    error UnreachableName(bytes name);

    /// @dev Error when the resolver profile cannot be answered.
    ///      Error selector: `0x7b1c461b`
    /// @param selector The function selector of the resolver profile.
    error UnsupportedResolverProfile(bytes4 selector);

    /// @dev Maximum number of calls in a `multicall()`.
    //       Actual limit: gateway proof size and/or gas limit.
    uint8 public immutable MAX_MULTICALLS = 32;

    /// @dev Error when the number of calls in a `multicall()` is too large.
    ///      Error selector: `0xf752eecf`
    /// @param max The maximum number of calls.
    error MulticallTooLarge(uint256 max);

    constructor(
        IBaseRegistrar _ethRegistrarV1,
        IUniversalResolver _universalResolverV1,
        address _burnAddressV1,
        IGatewayVerifier _namechainVerifier,
        address _namechainDatastore,
        address _namechainEthRegistry
    ) Ownable(msg.sender) {
        ethRegistrarV1 = _ethRegistrarV1;
        universalResolverV1 = _universalResolverV1;
        burnAddressV1 = _burnAddressV1;
        namechainVerifier = _namechainVerifier;
        namechainDatastore = _namechainDatastore;
        namechainEthRegistry = _namechainEthRegistry;
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceID) public view virtual override(ERC165) returns (bool) {
        return type(IExtendedResolver).interfaceId == interfaceID || super.supportsInterface(interfaceID);
    }

    /// @dev Set the Namechain verifier.
    /// @param verifier The new verifier address.
    function setNamechainVerifier(IGatewayVerifier verifier) external onlyOwner {
        namechainVerifier = verifier;
    }

    /// @dev Count the number of labels before "eth".
    ///      Reverts if invalid name or not "*.eth".
    /// @param name The name to parse.
    /// @return node The namehash of the name.
    /// @return count The number of labels before "eth".
    /// @return offset2LD The offset of the 2LD.
    function _countLabels(bytes memory name) internal pure returns (bytes32 node, uint256 count, uint256 offset2LD) {
        node = NameCoder.namehash(name, 0); // validates the name
        uint256 offset;
        uint256 offset1LD;
        while (true) {
            uint256 size = uint8(name[offset]);
            if (size == 0) break;
            offset2LD = offset1LD;
            offset1LD = offset;
            offset += 1 + size;
            count++;
        }
        // verify the last label was "eth"
        (bytes32 labelHash,) = NameCoder.readLabel(name, offset1LD);
        if (labelHash != keccak256("eth")) {
            revert UnreachableName(name);
        }
        count--; // drop last label
    }

    /// @dev Split the calldata into individual calls.
    /// @param data The calldata.
    /// @return multi True if the calldata is a multicall.
    /// @return calls The individual calls.
    function _parseCalls(bytes calldata data) internal pure returns (bool multi, bytes[] memory calls) {
        multi = bytes4(data) == IMulticallable.multicall.selector;
        if (multi) {
            calls = abi.decode(data[4:], (bytes[]));
            if (calls.length > MAX_MULTICALLS) {
                revert MulticallTooLarge(MAX_MULTICALLS);
            }
        } else {
            calls = new bytes[](1);
            calls[0] = data;
        }
    }

    /// @dev Return true if the name is actively registered on V1.
    /// @param id The labelhash of the "eth" 2LD.
    function _isActiveRegistrationV1(uint256 id) internal view returns (bool) {
        return !ethRegistrarV1.available(id) && ethRegistrarV1.ownerOf(id) != burnAddressV1;
    }

    /// @dev Program to traverse a label in the RegistryDatastore.
    function _findResolverProgram() internal view returns (GatewayRequest memory req) {
        req = GatewayFetcher.newCommand();
        req.pushOutput(0); // parent registry
        req.follow().follow(); // entry[registry][labelHash]
        req.read(); // read registryData
        req.dup().shl(32).shr(192); // extract expiry
        req.push(block.timestamp).gt().assertNonzero(1); // require expiry > timestamp
        req.shl(96).shr(96); // extract registry
        req.offset(1).read().shl(96).shr(96); // read resolverData => extract resolver
        req.push(GatewayFetcher.newCommand().requireNonzero(1).setOutput(1)); // save resolver if set
        req.evalLoop(0, 1); // consume resolver, catch assert
        req.requireNonzero(1).setOutput(0); // require registry and save it
    }

    /// @inheritdoc IExtendedResolver
    /// @notice Callers should enable EIP-3668.
    /// @dev This function executes over multiple steps (step 1 of 2).
    ///
    /// `GatewayRequest` walkthrough:
    /// * The stack is loaded with labelhashes, excluding "eth".
    ///     * "sub.vitalik.eth" &rarr; `["sub", "vitalik"]`.
    /// * `output[0]` is set to the Namechain "eth" registry.
    /// * `_findResolverProgram()` is pushed onto the stack.
    /// * `evalLoop(flags, count)` pops the program and executes it `count` times,
    ///   consuming one labelhash from the stack and passing it to the program in a separate context.
    ///     * The default `count` is the full stack.
    ///     * If `EvalFlag.STOP_ON_FAILURE`, the loop terminates when the program throws.
    ///     * Unless `EvalFlag.KEEP_ARGS`, `count` stack arguments are consumed, even when the loop terminates early.
    /// * Before the program executes:
    ///     * The target is `namechainDatastore`.
    ///     * The slot is `SLOT_RD_ENTRIES`.
    ///     * The stack is `[labelhash]`.
    ///     * `output[0]` is the parent registry address.
    ///     * `output[1]` is the latest resolver address.
    /// * `pushOutput(0)` adds the `registry` to the stack.
    ///     * The stack is `[labelHash, registry]`.
    /// * `req.setSlot(SLOT_RD_ENTRIES).follow().follow()` &harr; `entries[registry][labelHash]`.
    ///     * `follow()` does a pop and uses the value as a mapping key.
    /// * The program terminates if the next registry is expired.
    /// * `output[1]` is updated if a resolver is set.
    /// * The program terminates if the next registry is unset.
    /// * `output[0]` is updated to the next registry.
    ///
    /// Pseudocode:
    /// ```
    /// registry = <eth>
    /// resolver = null
    /// for label of ["vitalik", "sub"]
    ///    (reg, res) = registry[label]
    ///    if (expired) break
    ///    if (res) resolver = res
    ///    if (!reg) break
    ///    registry = reg
    /// ````
    function resolve(bytes memory name, bytes calldata data) external view returns (bytes memory) {
        (bytes32 node, uint256 labelCount, uint256 offset) = _countLabels(name);
        (bytes32 labelHash,) = NameCoder.readLabel(name, offset);
        if (labelCount == 0 || _isActiveRegistrationV1(uint256(labelHash))) {
            ccipRead(
                address(universalResolverV1),
                abi.encodeCall(IUniversalResolver.resolve, (name, data)),
                this.resolveV1Callback.selector,
                ""
            );
        }
        (bool multi, bytes[] memory calls) = _parseCalls(data);
        GatewayRequest memory req = GatewayFetcher.newRequest(uint8(calls.length < 2 ? 2 : calls.length));
        offset = 0; // reset to start
        for (uint256 i; i < labelCount; i++) {
            (labelHash, offset) = NameCoder.readLabel(name, offset);
            req.push(NameUtils.getCanonicalId(uint256(labelHash)));
        }
        req.push(namechainEthRegistry).setOutput(0); // starting point
        req.setTarget(namechainDatastore);
        req.setSlot(SLOT_RD_ENTRIES);
        req.push(_findResolverProgram());
        req.evalLoop(EvalFlag.STOP_ON_FAILURE); // outputs = [registry, resolver]
        req.pushOutput(1).requireNonzero(EXIT_CODE_NO_RESOLVER).target(); // target resolver
        req.setSlot(SLOT_PR_VERSIONS);
        req.push(node); // leave on stack at offset 0
        req.pushOutput(0).follow(); // recordVersions[node]
        req.read(); // version, leave on stack at offset 1
        req.push(bytes("")).dup().setOutput(0).setOutput(1); // clear outputs
        uint256 errors;
        for (uint256 i; i < calls.length; i++) {
            bytes memory v = calls[i];
            bytes4 selector = bytes4(v);
            if (selector == IAddrResolver.addr.selector) {
                req.setSlot(SLOT_PR_ADDRESSES);
                req.dup2().follow().follow().push(60).follow(); // versionable_addresses[version][node][60]
            } else if (selector == IAddressResolver.addr.selector) {
                (, uint256 coinType) = abi.decode(BytesUtils.substring(v, 4, v.length - 4), (bytes32, uint256));
                req.setSlot(SLOT_PR_ADDRESSES);
                req.dup2().follow().follow().push(coinType).follow(); // versionable_addresses[version][node][coinType]
            } else if (selector == ITextResolver.text.selector) {
                (, string memory key) = abi.decode(BytesUtils.substring(v, 4, v.length - 4), (bytes32, string));
                req.setSlot(SLOT_PR_TEXTS);
                req.dup2().follow().follow().push(key).follow(); // versionable_texts[version][node][key]
            } else if (selector == IContentHashResolver.contenthash.selector) {
                req.setSlot(SLOT_PR_CONTENTHASHES);
                req.dup2().follow().follow(); // versionable_hashes[version][node]
            } else if (selector == INameResolver.name.selector) {
                req.setSlot(SLOT_PR_NAMES);
                req.dup2().follow().follow(); // versionable_names[version][node]
            } else if (multi) {
                calls[i] = abi.encodeWithSelector(UnsupportedResolverProfile.selector, selector);
                errors++;
                continue;
            } else {
                revert UnsupportedResolverProfile(bytes4(v));
            }
            req.readBytes().setOutput(uint8(i));
        }
        if (multi && errors == calls.length) {
            return abi.encode(calls); // return immediate if all errors (or 0-calls)
        }
        fetch(namechainVerifier, req, this.resolveV2Callback.selector, abi.encode(name, multi, calls), new string[](0));
    }

    /// @dev V1 CCIP-Read callback for `resolve()` (step 2 of 2).
    /// @param response The response data from `UniversalResolver`.
    /// @return result The abi-encoded result.
    function resolveV1Callback(bytes calldata response, bytes calldata /*extraData*/ )
        external
        pure
        returns (bytes memory result)
    {
        (result,) = abi.decode(response, (bytes, address));
    }

    /// @dev V2 CCIP-Read callback for `resolve()` (step 2 of 2).
    /// @param values The outputs from the `GatewayRequest`.
    /// @param exitCode The exit code from the `GatewayRequest`.
    /// @param extraData The contextual data passed from `resolve()`.
    /// @return result The abi-encoded result.
    function resolveV2Callback(bytes[] calldata values, uint8 exitCode, bytes calldata extraData)
        external
        pure
        returns (bytes memory result)
    {
        (bytes memory name, bool multi, bytes[] memory calls) = abi.decode(extraData, (bytes, bool, bytes[]));
        if (exitCode == EXIT_CODE_NO_RESOLVER) {
            revert UnreachableName(name);
        }
        if (multi) {
            for (uint256 i; i < calls.length; i++) {
                calls[i] = _prepareResponse(calls[i], values[i]);
            }
            return abi.encode(calls);
        } else {
            return _prepareResponse(calls[0], values[0]);
        }
    }

    /// @dev Prepare response based on the request.
    /// @param data The original request (or error).
    /// @param value The response from the gateway.
    /// @return response The abi-encoded response for the request.
    function _prepareResponse(bytes memory data, bytes memory value) internal pure returns (bytes memory response) {
        if (bytes4(data) == UnsupportedResolverProfile.selector) {
            return data;
        } else if (bytes4(data) == IAddrResolver.addr.selector) {
            return abi.encode(address(bytes20(value)));
        } else {
            return abi.encode(value);
        }
    }
}
