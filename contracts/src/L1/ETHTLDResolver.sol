// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {CCIPReader} from "@ens/contracts/ccipRead/CCIPReader.sol";
import {IGatewayProvider} from "@ens/contracts/ccipRead/IGatewayProvider.sol";
import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {IMulticallable} from "@ens/contracts/resolvers/IMulticallable.sol";
import {IABIResolver} from "@ens/contracts/resolvers/profiles/IABIResolver.sol";
import {IAddressResolver} from "@ens/contracts/resolvers/profiles/IAddressResolver.sol";
import {IAddrResolver} from "@ens/contracts/resolvers/profiles/IAddrResolver.sol";
import {IContentHashResolver} from "@ens/contracts/resolvers/profiles/IContentHashResolver.sol";
import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";
import {IHasAddressResolver} from "@ens/contracts/resolvers/profiles/IHasAddressResolver.sol";
import {IInterfaceResolver} from "@ens/contracts/resolvers/profiles/IInterfaceResolver.sol";
import {INameResolver} from "@ens/contracts/resolvers/profiles/INameResolver.sol";
import {IPubkeyResolver} from "@ens/contracts/resolvers/profiles/IPubkeyResolver.sol";
import {ITextResolver} from "@ens/contracts/resolvers/profiles/ITextResolver.sol";
import {ResolverFeatures} from "@ens/contracts/resolvers/ResolverFeatures.sol";
import {RegistryUtils as RegistryUtilsV1} from "@ens/contracts/universalResolver/RegistryUtils.sol";
import {INameWrapper} from "@ens/contracts/wrapper/INameWrapper.sol";
import {ResolverCaller} from "@ens/contracts/universalResolver/ResolverCaller.sol";
import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";
import {ENSIP19, COIN_TYPE_ETH, COIN_TYPE_DEFAULT} from "@ens/contracts/utils/ENSIP19.sol";
import {IERC7996} from "@ens/contracts/utils/IERC7996.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {GatewayFetcher} from "@unruggable/gateways/contracts/GatewayFetcher.sol";
import {
    GatewayFetchTarget,
    IGatewayVerifier
} from "@unruggable/gateways/contracts/GatewayFetchTarget.sol";
import {GatewayRequest, EvalFlag} from "@unruggable/gateways/contracts/GatewayRequest.sol";

import {DedicatedResolverLayout} from "../common/DedicatedResolverLayout.sol";
import {IRegistryResolver} from "../common/IRegistryResolver.sol";
import {NameUtils} from "../common/NameUtils.sol";

/// @notice Resolver that performs ".eth" resolutions for Namechain (via gateway) or V1 (via fallback).
///
///         Mainnet ".eth" resolutions do not reach this resolver unless there are no resolvers set.
///
///         1. If there is an active V1 registration, resolve using Universal Resolver for V1.
///         2. Otherwise, resolve using Namechain.
///         3. If no resolver is found, reverts `UnreachableName`.
contract ETHTLDResolver is
    IExtendedResolver,
    IERC7996,
    IRegistryResolver,
    GatewayFetchTarget,
    ResolverCaller,
    Ownable,
    ERC165
{
    using GatewayFetcher for GatewayRequest;

    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    /// @dev Storage layout of RegistryDatastore.
    uint256 private constant _SLOT_RD_ENTRIES = 0;

    /// @dev `GatewayRequest` exit code which indicates no resolver was found.
    uint8 private constant _EXIT_CODE_NO_RESOLVER = 2;

    INameWrapper public immutable NAME_WRAPPER;

    IBaseRegistrar public immutable ETH_REGISTRAR_V1;

    address public immutable BURN_ADDRESS_V1;

    address public immutable NAMECHAIN_DATASTORE;

    address public immutable NAMECHAIN_ETH_REGISTRY;

    /// @dev Shared batch gateway provider.
    IGatewayProvider public immutable BATCH_GATEWAY_PROVIDER;

    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    address public ethResolver;

    IGatewayVerifier public namechainVerifier;

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    /// @notice The resolver profile cannot be answered.
    /// @dev Error selector: `0x7b1c461b`
    error UnsupportedResolverProfile(bytes4 selector);

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        INameWrapper nameWrapper,
        IGatewayProvider batchGatewayProvider_,
        address burnAddressV1_,
        address ethResolver_,
        IGatewayVerifier namechainVerifier_,
        address namechainDatastore_,
        address namechainEthRegistry_
    ) Ownable(msg.sender) CCIPReader(DEFAULT_UNSAFE_CALL_GAS) {
        NAME_WRAPPER = nameWrapper;
        ETH_REGISTRAR_V1 = IBaseRegistrar(nameWrapper.ens().owner(NameUtils.ETH_NODE));
        BATCH_GATEWAY_PROVIDER = batchGatewayProvider_;
        BURN_ADDRESS_V1 = burnAddressV1_;
        NAMECHAIN_DATASTORE = namechainDatastore_;
        NAMECHAIN_ETH_REGISTRY = namechainEthRegistry_;

        ethResolver = ethResolver_;
        namechainVerifier = namechainVerifier_;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165) returns (bool) {
        return
            type(IExtendedResolver).interfaceId == interfaceId ||
            type(IERC7996).interfaceId == interfaceId ||
            type(IRegistryResolver).interfaceId == interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IERC7996
    function supportsFeature(bytes4 feature) external pure returns (bool) {
        return ResolverFeatures.RESOLVE_MULTICALL == feature;
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /// @notice Set the Namechain verifier.
    /// @param verifier The new verifier address.
    function setNamechainVerifier(IGatewayVerifier verifier) external onlyOwner {
        namechainVerifier = verifier;
    }

    /// @notice Set the resolver for "eth".
    /// @param resolver The new resolver address.
    function setETHResolver(address resolver) external onlyOwner {
        ethResolver = resolver;
    }

    /// @notice Same as `resolveWithRegistry()` but starts at "eth".
    function resolve(
        bytes calldata name,
        bytes calldata data
    ) external view returns (bytes memory) {
        return resolveWithRegistry(NAMECHAIN_ETH_REGISTRY, NameUtils.ETH_NODE, name, data);
    }

    /// @dev CCIP-Read callback for `resolve()` from calling `namechainVerifier`.
    ///
    /// @param values The outputs for `GatewayRequest`.
    /// @param exitCode The exit code for `GatewayRequest`.
    /// @param extraData The contextual data passed from `resolve()`.
    ///
    /// @return The abi-encoded response for the request.
    function resolveNamechainCallback(
        bytes[] calldata values,
        uint8 exitCode,
        bytes calldata extraData
    ) external pure returns (bytes memory) {
        State memory state = abi.decode(extraData, (State));
        if (exitCode == _EXIT_CODE_NO_RESOLVER) {
            revert UnreachableName(state.name);
        }
        bytes memory defaultAddress = values[state.data.length]; // stored at end
        if (state.multi) {
            for (uint256 i; i < state.data.length; ++i) {
                state.data[i] = _prepareResponse(state.data[i], values[i], defaultAddress);
            }
            return abi.encode(state.data);
        } else {
            return _prepareResponse(state.data[0], values[0], defaultAddress);
        }
    }

    /// @dev Determine if actively registered on V1.
    /// @param labelHash The labelhash of the "eth" 2LD.
    /// @return `true` if the registration is active.
    function isActiveRegistrationV1(uint256 labelHash) public view returns (bool) {
        // TODO: add final migration logic
        return
            ETH_REGISTRAR_V1.nameExpires(labelHash) >= block.timestamp &&
            ETH_REGISTRAR_V1.ownerOf(labelHash) != BURN_ADDRESS_V1;
    }

    /// @notice Resolve `name` with the Namechain registry corresponding to `nodeSuffix`.
    ///         If `nodeSuffix` is "eth", checks Mainnet V1 before resolving on Namechain.
    /// @inheritdoc IRegistryResolver
    function resolveWithRegistry(
        address parentRegistry,
        bytes32 nodeSuffix,
        bytes calldata name,
        bytes calldata data
    ) public view returns (bytes memory) {
        (bool matched, , uint256 prevOffset, uint256 offset) = NameCoder.matchSuffix(
            name,
            0,
            nodeSuffix
        );
        if (!matched) {
            revert UnreachableName(name);
        }
        if (nodeSuffix == NameUtils.ETH_NODE) {
            if (offset == prevOffset) {
                callResolver(ethResolver, name, data, BATCH_GATEWAY_PROVIDER.gateways());
            }
            (bytes32 labelHash, ) = NameCoder.readLabel(name, prevOffset);
            if (isActiveRegistrationV1(uint256(labelHash))) {
                (address resolver, , ) = RegistryUtilsV1.findResolver(NAME_WRAPPER.ens(), name, 0);
                callResolver(resolver, name, data, BATCH_GATEWAY_PROVIDER.gateways());
            }
        }
        bytes[] memory calls;
        bool multi = bytes4(data) == IMulticallable.multicall.selector;
        if (multi) {
            calls = abi.decode(data[4:], (bytes[]));
        } else {
            calls = new bytes[](1);
            calls[0] = data;
        }
        return _resolveNamechain(State(parentRegistry, name, offset, multi, calls));
    }

    // solhint-disable namechain/ordering
    /// @dev State of Namechain resolution.
    struct State {
        address registry; // starting parent registry
        bytes name;
        uint256 nameLength; // name[:nameLength] are the labels to resolve
        bool multi; // true if multicall
        bytes[] data;
    }
    // solhint-enable namechain/ordering

    // solhint-disable private-vars-leading-underscore
    /// @notice Resolve `state.name[:state.nameLength]` on Namechain starting at `state.registry`.
    ///
    /// @dev This function executes over multiple steps.
    ///
    ///      `GatewayRequest` walkthrough:
    ///      * The stack is loaded with labelhashes:
    ///          * "sub.vitalik" &rarr; `["sub", "vitalik"]`.
    ///      * `output[0]` is set to the Namechain "eth" registry.
    ///      * A traversal program is pushed onto the stack.
    ///      * `evalLoop(flags, count)` pops the program and executes it `count` times,
    ///        consuming one labelhash from the stack and passing it to the program in a separate context.
    ///          * The default `count` is the full stack.
    ///          * If `EvalFlag.STOP_ON_FAILURE`, the loop terminates when the program throws.
    ///          * Unless `EvalFlag.KEEP_ARGS`, `count` stack arguments are consumed, even when the loop terminates early.
    ///      * Before the program executes:
    ///          * The target is `namechainDatastore`.
    ///          * The slot is `SLOT_RD_ENTRIES`.
    ///          * The stack is `[labelhash]`.
    ///          * `output[0]` is the parent registry address.
    ///          * `output[1]` is the latest resolver address.
    ///      * `pushOutput(0)` adds the `registry` to the stack.
    ///          * The stack is `[labelHash, registry]`.
    ///      * `req.setSlot(SLOT_RD_ENTRIES).follow().follow()` &harr; `entries[registry][labelHash]`.
    ///          * `follow()` does a pop and uses the value as a mapping key.
    ///      * The program terminates if the next registry is expired.
    ///      * `output[1]` contains the resolver if one is set.
    ///      * The program terminates if the next registry is unset.
    ///      * `output[0]` contains the next registry in the chain.
    ///
    ///      Pseudocode:
    ///      ```
    ///      registry = <registry>
    ///      resolver = null
    ///      for label of name.slice(-length).split('.').reverse()
    ///         (reg, res) = datastore.getSubregistry(reg, label)
    ///         if (expired) break
    ///         if (res) resolver = res
    ///         if (!reg) break
    ///         registry = reg
    ///      ```
    function _resolveNamechain(State memory state) public view returns (bytes memory) {
        // output[ 0] = registry
        // output[ 1] = last non-zero resolver
        // output[-1] = default address
        uint8 max = uint8(state.data.length);
        GatewayRequest memory req = GatewayFetcher.newRequest(max < 2 ? 2 : max + 1);
        {
            uint256 offset;
            while (offset < state.nameLength) {
                bytes32 labelHash;
                (labelHash, offset) = NameCoder.readLabel(state.name, offset);
                req.push(NameUtils.getCanonicalId(uint256(labelHash)));
            }
        }
        req.push(state.registry).setOutput(0); // starting point
        req.setTarget(NAMECHAIN_DATASTORE);
        req.setSlot(_SLOT_RD_ENTRIES);
        {
            // program to traverse one label in the RegistryDatastore
            GatewayRequest memory cmd = GatewayFetcher.newCommand();
            cmd.pushOutput(0); // parent registry
            cmd.follow().follow(); // entry[registry][labelHash]
            cmd.read(); // read registryData (see: RegistryDatastore.sol)
            cmd.dup().shl(192).shr(192); // extract expiry (first 64 bits)
            cmd.push(block.timestamp).gt().assertNonzero(1); // require expiry > timestamp
            cmd.shr(96); // extract subregistry (shift past expiry+tokenVersionId)
            cmd.offset(1).read().shr(32); // read slot 1, shift past eacVersionId to get resolver
            cmd.push(
                GatewayFetcher.newCommand().requireNonzero(1).setOutput(1) // save resolver if set
            );
            cmd.evalLoop(0, 1); // consume resolver, catch assert
            cmd.requireNonzero(1).setOutput(0); // require registry and save it
            req.push(cmd);
        }
        req.evalLoop(EvalFlag.STOP_ON_FAILURE | EvalFlag.KEEP_ARGS); // outputs = [registry, resolver]
        req.pushOutput(1).requireNonzero(_EXIT_CODE_NO_RESOLVER).target(); // target resolver
        req.push(bytes("")).dup().setOutput(0).setOutput(1); // clear outputs
        uint8 errorCount; // number of errors
        for (uint8 i; i < state.data.length; ++i) {
            bytes memory v = state.data[i];
            bytes4 selector = bytes4(v);
            // NOTE: "node check" is NOT performed:
            // if (v.length < 36 || BytesUtils.readBytes32(v, 4) != node) {
            //     calls[i] = abi.encodeWithSelector(NodeMismatch.selector, node);
            //     continue;
            // }
            if (
                selector == IAddrResolver.addr.selector ||
                selector == IAddressResolver.addr.selector
            ) {
                uint256 coinType = selector == IAddrResolver.addr.selector
                    ? COIN_TYPE_ETH
                    : uint256(BytesUtils.readBytes32(v, 36));
                req
                    .setSlot(DedicatedResolverLayout.SLOT_ADDRESSES)
                    .push(coinType)
                    .follow()
                    .readBytes(); // _addresses[coinType]
                if (ENSIP19.chainFromCoinType(coinType) > 0) {
                    req.dup().length().isZero().pushOutput(max).plus().setOutput(uint8(max)); // count missing
                }
            } else if (selector == IHasAddressResolver.hasAddr.selector) {
                uint256 coinType = uint256(BytesUtils.readBytes32(v, 36));
                req.setSlot(DedicatedResolverLayout.SLOT_ADDRESSES).push(coinType).follow().read(); // _addresses[coinType] head slot
            } else if (selector == ITextResolver.text.selector) {
                (, string memory key) = abi.decode(
                    BytesUtils.substring(v, 4, v.length - 4),
                    (bytes32, string)
                );
                // uint256 jump = 4 + uint256(BytesUtils.readBytes32(v, 36));
                // uint256 size = uint256(BytesUtils.readBytes32(v, jump));
                // bytes memory key = BytesUtils.substring(v, jump + 32, size);
                req.setSlot(DedicatedResolverLayout.SLOT_TEXTS).push(key).follow().readBytes(); // _texts[key]
            } else if (selector == IContentHashResolver.contenthash.selector) {
                req.setSlot(DedicatedResolverLayout.SLOT_CONTENTHASH).readBytes(); // _contenthash
            } else if (selector == INameResolver.name.selector) {
                req.setSlot(DedicatedResolverLayout.SLOT_PRIMARY).readBytes(); // _primary
            } else if (selector == IPubkeyResolver.pubkey.selector) {
                req.setSlot(DedicatedResolverLayout.SLOT_PUBKEY).read(2); // _pubkey (x and y)
            } else if (selector == IInterfaceResolver.interfaceImplementer.selector) {
                bytes4 interfaceID = bytes4(BytesUtils.readBytes32(v, 36));
                req
                    .setSlot(DedicatedResolverLayout.SLOT_INTERFACES)
                    .push(interfaceID)
                    .follow()
                    .read(); // _interfaces[interfaceID]
            } else if (selector == IABIResolver.ABI.selector) {
                uint256 bits = uint256(BytesUtils.readBytes32(v, 36));
                for (uint256 contentType = 1 << 255; contentType > 0; contentType >>= 1) {
                    if ((bits & contentType) != 0) {
                        req.push(contentType); // stack overflow if too many bits
                    }
                }
                // program to check one stored abi
                GatewayRequest memory cmd = GatewayFetcher.newCommand();
                cmd.dup().follow().readBytes(); // read abi, but keep contentType on stack
                cmd.dup().length().assertNonzero(1); // require length > 0
                cmd.concat().setOutput(i); // save contentType + bytes
                req.push(cmd);
                req.setSlot(DedicatedResolverLayout.SLOT_ABIS);
                req.evalLoop(EvalFlag.STOP_ON_SUCCESS);
                continue;
            } else {
                ++errorCount;
                state.data[i] = abi.encodeWithSelector(
                    UnsupportedResolverProfile.selector,
                    selector
                );
                continue;
            }
            req.setOutput(i);
        }
        if (errorCount == max) {
            if (state.multi) {
                return abi.encode(state.data); // all calls failed
            } else {
                bytes memory v = state.data[0];
                assembly {
                    revert(add(v, 32), mload(v)) // revert with the call that failed
                }
            }
        }
        req.pushOutput(max).requireNonzero(0); // stop if no missing
        req
            .setSlot(DedicatedResolverLayout.SLOT_ADDRESSES)
            .push(COIN_TYPE_DEFAULT)
            .follow()
            .readBytes(); // _addresses[COIN_TYPE_DEFAULT]
        req.setOutput(uint8(max)); // save default address at end
        fetch(
            namechainVerifier,
            req,
            this.resolveNamechainCallback.selector, // ==> step 2
            abi.encode(state),
            new string[](0)
        );
    }
    // solhint-enable private-vars-leading-underscore

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    /// @dev Prepare response based on the request.
    ///
    /// @param data The original request (or error).
    /// @param value The response from the gateway.
    ///
    /// @return The abi-encoded response for the request.
    function _prepareResponse(
        bytes memory data,
        bytes memory value,
        bytes memory defaultAddress
    ) internal pure returns (bytes memory) {
        bytes4 selector = bytes4(data);
        if (selector == UnsupportedResolverProfile.selector) {
            return data;
        } else if (selector == IAddrResolver.addr.selector) {
            if (value.length == 0) {
                value = defaultAddress;
            }
            return abi.encode(address(bytes20(value)));
        } else if (selector == IAddressResolver.addr.selector) {
            if (
                value.length == 0 &&
                ENSIP19.chainFromCoinType(uint256(BytesUtils.readBytes32(data, 36))) > 0
            ) {
                value = defaultAddress;
            }
            return abi.encode(value);
        } else if (selector == IHasAddressResolver.hasAddr.selector) {
            return abi.encode(bytes32(value) != bytes32(0));
        } else if (
            selector == IPubkeyResolver.pubkey.selector ||
            selector == IInterfaceResolver.interfaceImplementer.selector
        ) {
            return value;
        } else if (selector == IABIResolver.ABI.selector) {
            uint256 contentType;
            if (value.length > 0) {
                assembly {
                    let ptr := add(value, 32)
                    contentType := mload(ptr) // extract contentType from first word
                    mstore(ptr, sub(mload(value), 32)) // reduce length
                    value := ptr // update pointer
                }
            }
            return abi.encode(contentType, value);
        } else {
            return abi.encode(value);
        }
    }
}
