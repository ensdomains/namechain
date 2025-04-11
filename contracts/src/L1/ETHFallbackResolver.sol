// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

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
import {IRegistry} from "../common/IRegistry.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";

contract ETHFallbackResolver is IExtendedResolver, GatewayFetchTarget, ERC165 {
    using GatewayFetcher for GatewayRequest;

    IRegistry public immutable ethRegistry;
    address public immutable namechainDatastore;
    address public immutable namechainEthRegistry;
    IGatewayVerifier public immutable namechainVerifier;

    bytes constant DOT_ETH_SUFFIX = "\x03eth\x00";

    uint8 constant EXIT_CODE_NO_RESOLVER = 2;

    uint256 constant RESERVED_OUTPUTS = 2;

    /// @dev Storage layout of RegistryDatastore.
    uint256 constant SLOT_RD_ENTRIES = 0;

    /// @dev Storage layout of PublicResolver.
    uint256 constant SLOT_PR_VERSIONS = 0;
    uint256 constant SLOT_PR_ADDRESSES = 2;
    uint256 constant SLOT_PR_CONTENTHASHES = 3;
    uint256 constant SLOT_PR_NAMES = 8;
    uint256 constant SLOT_PR_TEXTS = 10;

    /// @dev Error when `name` does not exist.
    /// @param name The DNS-encoded ENS name.
    error UnreachableName(bytes name);

    /// @dev Error when the resolver profile that cannot be answered.
    /// @param selector The function selector of the resolver profile.
    error UnsupportedResolverProfile(bytes4 selector);

    uint256 public immutable MAX_MULTICALLS = 32; // cant be more than 253

    /// @dev Error when the number of calls in a multicall() is too large.
    /// @param max The maximum number of calls.
    error MulticallTooLarge(uint256 max);

    constructor(
        IRegistry _ethRegistry,
        address _namechainDatastore,
        address _namechainEthRegistry,
        IGatewayVerifier _namechainVerifier
    ) {
        ethRegistry = _ethRegistry;
        namechainDatastore = _namechainDatastore;
        namechainEthRegistry = _namechainEthRegistry;
        namechainVerifier = _namechainVerifier;
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceID) public view virtual override(ERC165) returns (bool) {
        return type(IExtendedResolver).interfaceId == interfaceID || super.supportsInterface(interfaceID);
    }

    /// @dev Parse `"\x01a\x02bb\x03ccc\x03eth\x00"` into `[0, 2, 5]`.
    ///      Reverts if not ".eth" or the name is invalid.
    ///      Returns [] for "eth".
    /// @param name The name to parse.
    /// @return offsets The byte-offsets of each label excluding ".eth".
    function _parseName(bytes memory name) internal pure returns (uint256[] memory offsets) {
        uint256 offset;
        uint256 count;
        while (true) {
            if (BytesUtils.equals(name, offset, DOT_ETH_SUFFIX, 0, DOT_ETH_SUFFIX.length)) {
                break;
            }
            if (count == offsets.length) {
                uint256[] memory v = new uint256[](count + 8);
                for (uint256 i; i < count; i++) {
                    v[i] = offsets[i];
                }
                offsets = v;
            }
            offsets[count++] = offset;
            (, offset) = NameCoder.readLabel(name, offset);
        }
        assembly {
            mstore(offsets, count)
        }
    }

    /// @dev Create program to traverse the RegistryDatastore.
    ///      Inputs: Output[0] = Parent Registry
    ///      Outputs: Output[0] = Child Registry, Output[1] = Resolver
    function _findResolverProgram() internal view returns (GatewayRequest memory req) {
        req = GatewayFetcher.newCommand();
        req.pushOutput(0); // parent registry
        req.setSlot(SLOT_RD_ENTRIES).follow().follow(); // entry[registry][labelHash]
        req.read(); // read registryData
        req.dup().shl(32).shr(192); // extract expiry
        req.push(block.timestamp).gt().assertNonzero(1); // require expiry > timestamp
        req.shl(96).shr(96); // extract registry
        req.offset(1).read().shl(96).shr(96); // read resolverData => extract resolver
        req.push(GatewayFetcher.newCommand().requireNonzero(1).setOutput(1)); // save resolver if set
        req.evalLoop(0, 1);
        req.requireNonzero(1).setOutput(0); // require registry and save it
    }

    /// @dev Split the calldata into calls.
    /// @param data The calldata.
    /// @return multi True if the calldata is a multicall.
    /// @return calls The individual calls.
    function _parseCalls(bytes calldata data) internal pure returns (bool multi, bytes[] memory calls) {
        multi = bytes4(data) == IMulticallable.multicall.selector;
        if (multi) {
            calls = abi.decode(data[4:], (bytes[]));
            if (calls.length >= MAX_MULTICALLS) {
                revert MulticallTooLarge(MAX_MULTICALLS);
            }
        } else {
            calls = new bytes[](1);
            calls[0] = data;
        }
    }

    /// @inheritdoc IExtendedResolver
    function resolve(bytes memory name, bytes calldata data) external view returns (bytes memory) {
        uint256[] memory offsets = _parseName(name);
        if (offsets.length == 0) {
            revert UnreachableName(name); // no records on "eth"
        }
        address resolver = ethRegistry.getResolver(NameUtils.readLabel(name, offsets[offsets.length - 1]));
        if (resolver != address(0) && resolver != address(this)) {
            revert UnreachableName(name); // invalid state: ejected and resolver exists and different from us
        }
        (bool multi, bytes[] memory calls) = _parseCalls(data);
        GatewayRequest memory req = GatewayFetcher.newRequest(uint8(RESERVED_OUTPUTS + calls.length));
        req.setTarget(namechainDatastore);
        for (uint256 i; i < offsets.length; i++) {
            (bytes32 labelHash,) = NameCoder.readLabel(name, offsets[i]);
            req.push(NameUtils.getCanonicalId(uint256(labelHash)));
        }
        req.push(namechainEthRegistry).setOutput(0); // starting point
        req.push(_findResolverProgram());
        req.evalLoop(EvalFlag.STOP_ON_FAILURE); // outputs = [registry, resolver]
        req.pushOutput(1).requireNonzero(EXIT_CODE_NO_RESOLVER).target(); // target resolver
        req.push(NameCoder.namehash(name, 0)); // node, leave on stack at offset 0
        req.setSlot(SLOT_PR_VERSIONS);
        req.pushStack(0).follow(); // recordVersions[node]
        req.read(); // version, leave on stack at offset 1
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
            req.readBytes().setOutput(uint8(RESERVED_OUTPUTS + i));
        }
        if (multi && errors == calls.length) {
            return abi.encode(calls);
        }
        fetch(namechainVerifier, req, this.resolveCallback.selector, abi.encode(name, multi, calls), new string[](0));
    }

    function resolveCallback(bytes[] calldata values, uint8 exitCode, bytes calldata extraData)
        external
        pure
        returns (bytes memory)
    {
        (bytes memory name, bool multi, bytes[] memory calls) = abi.decode(extraData, (bytes, bool, bytes[]));
        if (exitCode == EXIT_CODE_NO_RESOLVER) {
            revert UnreachableName(name);
        }
        if (multi) {
            for (uint256 i; i < calls.length; i++) {
                calls[i] = _prepareResponse(calls[i], values[RESERVED_OUTPUTS + i]);
            }
            return abi.encode(calls);
        } else {
            return _prepareResponse(calls[0], values[RESERVED_OUTPUTS]);
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
