// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {CCIPReader} from "@ens/contracts/ccipRead/CCIPReader.sol";
import {IGatewayProvider} from "@ens/contracts/ccipRead/IGatewayProvider.sol";
import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {IMulticallable} from "@ens/contracts/resolvers/IMulticallable.sol";
import {IABIResolver} from "@ens/contracts/resolvers/profiles/IABIResolver.sol";
import {IAddressResolver} from "@ens/contracts/resolvers/profiles/IAddressResolver.sol";
import {IAddrResolver} from "@ens/contracts/resolvers/profiles/IAddrResolver.sol";
import {ICompositeResolver} from "@ens/contracts/resolvers/profiles/ICompositeResolver.sol";
import {IContentHashResolver} from "@ens/contracts/resolvers/profiles/IContentHashResolver.sol";
import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";
import {IHasAddressResolver} from "@ens/contracts/resolvers/profiles/IHasAddressResolver.sol";
import {IInterfaceResolver} from "@ens/contracts/resolvers/profiles/IInterfaceResolver.sol";
import {INameResolver} from "@ens/contracts/resolvers/profiles/INameResolver.sol";
import {IPubkeyResolver} from "@ens/contracts/resolvers/profiles/IPubkeyResolver.sol";
import {ITextResolver} from "@ens/contracts/resolvers/profiles/ITextResolver.sol";
import {IVerifiableResolver} from "@ens/contracts/resolvers/profiles/IVerifiableResolver.sol";
import {ResolverFeatures} from "@ens/contracts/resolvers/ResolverFeatures.sol";
import {RegistryUtils} from "@ens/contracts/universalResolver/RegistryUtils.sol";
import {ResolverCaller} from "@ens/contracts/universalResolver/ResolverCaller.sol";
import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";
import {ENSIP19, COIN_TYPE_ETH, COIN_TYPE_DEFAULT} from "@ens/contracts/utils/ENSIP19.sol";
import {IERC7996} from "@ens/contracts/utils/IERC7996.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {INameWrapper} from "@ens/contracts/wrapper/INameWrapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {GatewayFetcher} from "@unruggable/gateways/contracts/GatewayFetcher.sol";
import {
    GatewayFetchTarget,
    IGatewayVerifier
} from "@unruggable/gateways/contracts/GatewayFetchTarget.sol";
import {GatewayRequest, EvalFlag} from "@unruggable/gateways/contracts/GatewayRequest.sol";

import {BridgeRolesLib} from "../../common/bridge/libraries/BridgeRolesLib.sol";
import {IPermissionedRegistry} from "../../common/registry/interfaces/IPermissionedRegistry.sol";
import {IRegistry} from "../../common/registry/interfaces/IRegistry.sol";
import {IRegistryDatastore} from "../../common/registry/interfaces/IRegistryDatastore.sol";
import {DedicatedResolverLib} from "../../common/resolver/libraries/DedicatedResolverLib.sol";
import {LibLabel} from "../../common/utils/LibLabel.sol";
import {LibRegistry} from "../../universalResolver/libraries/LibRegistry.sol";
import {L1BridgeController} from "../bridge/L1BridgeController.sol";

/// @notice Resolver that performs ".eth" resolutions for Namechain (via gateway) or V1 (via fallback).
///
/// 0. Mainnet ".eth" resolutions do not reach this resolver unless set directly or there are no resolvers.
/// 1. If there is an active V1 registration (unmigrated), resolve using V1 Registry.
/// 2. Otherwise, resolve using Namechain.
/// 3. If Namechain resolver is 0x1 (pre-migration), use V1.
/// 4. If Namechain resolver is 0x2 (post-ejection), use V2 on Mainnet (w/expiry circumvention).
/// 5. If no resolver is found, reverts `UnreachableName`.
///
///                       *** Mainnet (L1) ***                |                *** Namechain (L2) ***
///                                                           |
///                             <root> (RootRegistry)         |   Gateway
///                                |                          |      |
///                              <eth> (ETHRegistry) - - - - -|- - - + - - - -> <eth> (ETHRegistry)
///             ____________ETHTLDResolver____________        |             (null resolver)
///            /                   |                  \       |             /             \
///    0.) <alice>        1.) <unmigrated>             *      |      2.) <bob>           5. ??? ==> UnreachableName
///  DedicatedResolver       PublicResolver                   |   DedicatedResolver
///   => Mainnet (V2)        => Mainnet (V1)                  |   => Namechain (V2)
///
contract ETHTLDResolver is
    ICompositeResolver,
    IVerifiableResolver,
    IERC7996,
    GatewayFetchTarget,
    ResolverCaller,
    Ownable,
    ERC165
{
    using GatewayFetcher for GatewayRequest;

    ////////////////////////////////////////////////////////////////////////
    // Types
    ////////////////////////////////////////////////////////////////////////

    /// @dev Determines how a name should be resolved.
    enum NameState {
        // name is on namechain
        NAMECHAIN,
        // name is in-flight to namechain but still in V1
        PRE_MIGRATION, // = address(0x1)
        // name is in-flight to nanechain and unregistered in V2
        POST_EJECTION //  = address(0x2)
    }

    /// @dev Determines if the default EVM address should be included.
    enum DefaultEVMState {
        ABSENT, // no addr(evm) => no default needed
        NEED, // there is addr(evm) but no default
        HAVE // there is addr(evm:0)
    }

    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    /// @dev Storage layout of RegistryDatastore.
    uint256 private constant _SLOT_RD_ENTRIES = 0;

    /// @dev `GatewayRequest` exit code which indicates no resolver was found.
    uint8 private constant _EXIT_CODE_NO_RESOLVER = 2;

    INameWrapper public immutable NAME_WRAPPER;

    IBaseRegistrar public immutable ETH_REGISTRAR_V1;

    IPermissionedRegistry public immutable ETH_REGISTRY;

    L1BridgeController public immutable L1_BRIDGE_CONTROLLER;

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
        IGatewayProvider batchGatewayProvider,
        IPermissionedRegistry ethRegistry,
        L1BridgeController l1BridgeController,
        address ethResolver_,
        IGatewayVerifier namechainVerifier_,
        address namechainDatastore,
        address namechainEthRegistry
    ) Ownable(msg.sender) CCIPReader(DEFAULT_UNSAFE_CALL_GAS) {
        NAME_WRAPPER = nameWrapper;
        ETH_REGISTRAR_V1 = nameWrapper.registrar();
        BATCH_GATEWAY_PROVIDER = batchGatewayProvider;
        ETH_REGISTRY = ethRegistry;
        L1_BRIDGE_CONTROLLER = l1BridgeController;
        NAMECHAIN_DATASTORE = namechainDatastore;
        NAMECHAIN_ETH_REGISTRY = namechainEthRegistry;

        ethResolver = ethResolver_;
        namechainVerifier = namechainVerifier_;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165) returns (bool) {
        return
            type(IExtendedResolver).interfaceId == interfaceId ||
            type(ICompositeResolver).interfaceId == interfaceId ||
            type(IVerifiableResolver).interfaceId == interfaceId ||
            type(IERC7996).interfaceId == interfaceId ||
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

    /// @notice Resolve `name` with the Namechain registry.
    ///         Checks Mainnet V1 before resolving on Namechain.
    function resolve(
        bytes calldata name,
        bytes calldata data
    ) external view returns (bytes memory result) {
        address resolver = _determineMainnetResolver(name);
        if (resolver == address(0)) {
            bytes[] memory calls;
            bool multi = bytes4(data) == IMulticallable.multicall.selector;
            if (multi) {
                calls = abi.decode(data[4:], (bytes[]));
            } else {
                calls = new bytes[](1);
                calls[0] = data;
            }
            result = _resolveNamechain(name, multi, calls);
        } else {
            callResolver(resolver, name, data, false, "", BATCH_GATEWAY_PROVIDER.gateways());
        }
    }

    /// @inheritdoc IVerifiableResolver
    function verifierMetadata(
        bytes calldata name
    ) external view returns (address verifier, string[] memory gateways) {
        if (_determineMainnetResolver(name) == address(0)) {
            verifier = address(namechainVerifier);
            gateways = namechainVerifier.gatewayURLs();
        }
    }

    /// @inheritdoc ICompositeResolver
    function requiresOffchain(bytes calldata name) external view returns (bool offchain) {
        offchain = _determineMainnetResolver(name) == address(0);
    }

    /// @inheritdoc ICompositeResolver
    /// @dev This function executes over multiple steps.
    /// * `getResolver("eth") = (ethResolver, false)`
    /// * `getResolver(<not .eth>)` reverts
    /// * `getResolver(<unmigrated .eth>) = (<L1 resolver>, false)`
    /// * `getResolver(<namechain .eth>) = (<L2 resolver>, true)`
    /// * `getResolver(<unregistered .eth) = (address(0), true)`
    function getResolver(bytes calldata name) external view returns (address, bool) {
        address resolver = _determineMainnetResolver(name);
        if (resolver != address(0)) {
            return (resolver, false);
        }
        fetch(
            namechainVerifier,
            _createRequest(0, name),
            this.getResolverCallback.selector, // ==> step 2,
            name,
            new string[](0)
        );
    }

    /// @notice CCIP-Read callback for `getResolver()`.
    function getResolverCallback(
        bytes[] calldata values,
        uint8 /*exitCode*/,
        bytes calldata name
    ) external view returns (address resolver, bool offchain) {
        NameState state = _nameStateFrom(values[1]);
        if (state == NameState.NAMECHAIN) {
            resolver = address(uint160(uint256(bytes32(values[1]))));
            offchain = true;
        } else {
            resolver = _determineInflightResolver(name, state);
        }
    }

    /// @notice CCIP-Read callback for `resolve()`.
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
    ) external view returns (bytes memory) {
        (bytes memory name, bool multi, bytes[] memory m) = abi.decode(
            extraData,
            (bytes, bool, bytes[])
        );
        if (exitCode == _EXIT_CODE_NO_RESOLVER) {
            address resolver = _determineInflightResolver(name, _nameStateFrom(values[1]));
            if (address(resolver) == address(0)) {
                revert UnreachableName(name);
            }
            callResolver(
                resolver,
                name,
                multi ? abi.encodeCall(IMulticallable.multicall, (m)) : m[0],
                false,
                "",
                BATCH_GATEWAY_PROVIDER.gateways()
            );
        }
        bytes memory defaultAddress = values[m.length]; // stored at end
        if (multi) {
            for (uint256 i; i < m.length; ++i) {
                m[i] = _prepareResponse(m[i], values[i], defaultAddress);
            }
            return abi.encode(m);
        } else {
            return _prepareResponse(m[0], values[0], defaultAddress);
        }
    }

    /// @dev Determine if actively registered on V1.
    ///
    /// @param labelHash The labelhash of the "eth" 2LD.
    ///
    /// @return `true` if the registration is active.
    function isActiveRegistrationV1(bytes32 labelHash) public view returns (bool) {
        return
            ETH_REGISTRAR_V1.nameExpires(uint256(labelHash)) >= block.timestamp &&
            !L1_BRIDGE_CONTROLLER.hasRootRoles(
                BridgeRolesLib.ROLE_EJECTOR,
                ETH_REGISTRAR_V1.ownerOf(uint256(labelHash))
            );
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    /// @dev Create `GatewayRequest` for registry traversal.
    ///
    /// @param outputs The number of outputs for the request.
    /// @param name The DNS-encoded .eth name to resolve.
    ///
    /// `GatewayRequest` walkthrough:
    /// * The stack is loaded with labelhashes:
    ///     * "sub.vitalik" &rarr; `["sub", "vitalik"]`.
    /// * `output[0]` is set to the Namechain "eth" registry.
    /// * A traversal program is pushed onto the stack.
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
    /// * `output[1]` contains the resolver if one is set.
    /// * The program terminates if the next registry is unset.
    /// * `output[0]` contains the next registry in the chain.
    ///
    /// Pseudocode:
    /// ```
    /// registry = <registry>
    /// resolver = null
    /// for label of name.slice(-length).split('.').reverse()
    ///    (reg, res) = datastore.getSubregistry(reg, label)
    ///    if (expired) break
    ///    if (res) resolver = res
    ///    if (!reg) break
    ///    registry = reg
    /// ```
    function _createRequest(
        uint8 outputs,
        bytes memory name
    ) internal view returns (GatewayRequest memory req) {
        req = GatewayFetcher.newRequest(outputs < 2 ? 2 : outputs);
        uint256 offset;
        while (offset < name.length - 5) {
            bytes32 labelHash; //     ^ "3eth0".length = 5
            (labelHash, offset) = NameCoder.readLabel(name, offset);
            req.push(LibLabel.getCanonicalId(uint256(labelHash)));
        }
        req.push(NAMECHAIN_ETH_REGISTRY).setOutput(0); // starting point
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
    }

    /// @notice Resolve `name` on Namechain.
    ///
    /// @dev This function executes over multiple steps.
    function _resolveNamechain(
        bytes memory name,
        bool multi,
        bytes[] memory m
    ) internal view returns (bytes memory) {
        // output[ 0] = registry
        // output[ 1] = last non-zero resolver
        // output[-1] = default address
        uint8 max = uint8(m.length);
        GatewayRequest memory req = _createRequest(max + 1, name);
        req.pushOutput(1).push(uint256(type(NameState).max)).gt().assertNonzero(
            _EXIT_CODE_NO_RESOLVER
        ); // is this a real resolver?
        req.pushOutput(1).target(); // target resolver
        req.push(DedicatedResolverLib.NAMED_SLOT); // save slot offset
        req.push(bytes("")).dup().setOutput(0).setOutput(1); // clear outputs
        uint8 errorCount; // number of errors
        DefaultEVMState evmState = DefaultEVMState.ABSENT;
        for (uint8 i; i < m.length; ++i) {
            bytes memory v = m[i];
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
                req.pushStack(0).push(DedicatedResolverLib.OFFSET_ADDRESSES).plus().slot();
                req.push(coinType).follow().readBytes(); // _addresses[coinType]
                if (evmState != DefaultEVMState.HAVE) {
                    if (coinType == COIN_TYPE_DEFAULT) {
                        evmState = DefaultEVMState.HAVE;
                        req.dup().setOutput(max); // copy to end
                    } else if (ENSIP19.chainFromCoinType(coinType) > 0) {
                        evmState = DefaultEVMState.NEED;
                    }
                }
            } else if (selector == IHasAddressResolver.hasAddr.selector) {
                uint256 coinType = uint256(BytesUtils.readBytes32(v, 36));
                req.pushStack(0).push(DedicatedResolverLib.OFFSET_ADDRESSES).plus().slot();
                req.push(coinType).follow().read(); // _addresses[coinType] head slot
            } else if (selector == ITextResolver.text.selector) {
                (, string memory key) = abi.decode(
                    BytesUtils.substring(v, 4, v.length - 4),
                    (bytes32, string)
                );
                // uint256 jump = 4 + uint256(BytesUtils.readBytes32(v, 36));
                // uint256 size = uint256(BytesUtils.readBytes32(v, jump));
                // bytes memory key = BytesUtils.substring(v, jump + 32, size);
                req.pushStack(0).push(DedicatedResolverLib.OFFSET_TEXTS).plus().slot();
                req.push(key).follow().readBytes(); // _texts[key]
            } else if (selector == IContentHashResolver.contenthash.selector) {
                req.pushStack(0).push(DedicatedResolverLib.OFFSET_CONTENTHASH).plus().slot();
                req.readBytes(); // _contenthash
            } else if (selector == INameResolver.name.selector) {
                req.pushStack(0).push(DedicatedResolverLib.OFFSET_NAME).plus().slot();
                req.readBytes(); // _primary
            } else if (selector == IPubkeyResolver.pubkey.selector) {
                req.pushStack(0).push(DedicatedResolverLib.OFFSET_PUBKEY).plus().slot();
                req.read(2); // _pubkey (x and y)
            } else if (selector == IInterfaceResolver.interfaceImplementer.selector) {
                bytes4 interfaceID = bytes4(BytesUtils.readBytes32(v, 36));
                req.pushStack(0).push(DedicatedResolverLib.OFFSET_INTERFACES).plus().slot();
                req.push(interfaceID).follow().read(); // _interfaces[interfaceID]
            } else if (selector == IABIResolver.ABI.selector) {
                uint256 bits = uint256(BytesUtils.readBytes32(v, 36));
                uint256 count;
                for (uint256 contentType = 1 << 255; contentType > 0; contentType >>= 1) {
                    if ((bits & contentType) != 0) {
                        req.push(contentType); // stack overflow if too many bits
                        ++count;
                    }
                }
                // program to check one stored abi
                GatewayRequest memory cmd = GatewayFetcher.newCommand();
                cmd.dup().follow().readBytes(); // read abi, but keep contentType on stack
                cmd.dup().length().assertNonzero(1); // require length > 0
                cmd.concat().setOutput(i); // save contentType + bytes
                req.push(cmd);
                req.pushStack(0).push(DedicatedResolverLib.OFFSET_ABIS).plus().slot();
                req.evalLoop(EvalFlag.STOP_ON_SUCCESS, count);
                continue;
            } else {
                ++errorCount;
                m[i] = abi.encodeWithSelector(UnsupportedResolverProfile.selector, selector);
                continue;
            }
            req.setOutput(i);
        }
        if (errorCount == max) {
            if (multi) {
                return abi.encode(m); // all calls failed
            } else {
                bytes memory v = m[0];
                assembly {
                    revert(add(v, 32), mload(v)) // revert with the call that failed
                }
            }
        }
        if (evmState == DefaultEVMState.NEED) {
            req.pushStack(0).push(DedicatedResolverLib.OFFSET_ADDRESSES).plus().slot(); // load slot offset
            req.push(COIN_TYPE_DEFAULT).follow().readBytes(); // _addresses[COIN_TYPE_DEFAULT]
            req.setOutput(max); // save default address at end
        }
        fetch(
            namechainVerifier,
            req,
            this.resolveNamechainCallback.selector, // ==> step 2
            abi.encode(name, multi, m),
            new string[](0)
        );
    }

    /// @dev Determine underlying Mainnet resolver or null if offchain.
    function _determineMainnetResolver(bytes memory name) internal view returns (address resolver) {
        (bool matched, , uint256 prevOffset, uint256 offset) = NameCoder.matchSuffix(
            name,
            0,
            NameCoder.ETH_NODE
        );
        if (!matched) {
            revert UnreachableName(name);
        }
        if (offset == prevOffset) {
            return ethResolver;
        }
        (bytes32 labelHash, ) = NameCoder.readLabel(name, prevOffset);
        if (isActiveRegistrationV1(labelHash)) {
            (resolver, , ) = RegistryUtils.findResolver(NAME_WRAPPER.ens(), name, 0);
            if (resolver == address(this)) {
                resolver = address(0);
            }
        }
    }

    /// @dev Determine underlying resolver while `name` is inflight to Namechain.
    function _determineInflightResolver(
        bytes memory name,
        NameState state
    ) internal view returns (address resolver) {
        if (state == NameState.PRE_MIGRATION) {
            (resolver, , ) = RegistryUtils.findResolver(NAME_WRAPPER.ens(), name, 0);
        } else if (state == NameState.POST_EJECTION) {
            (, , uint256 offset, ) = NameCoder.matchSuffix(name, 0, NameCoder.ETH_NODE);
            (string memory label, ) = NameCoder.extractLabel(name, offset);
            // circumvent ETH_REGISTRY.getResolver() since name was unregistered()
            (, IRegistryDatastore.Entry memory entry) = ETH_REGISTRY.getNameData(label);
            (, resolver) = LibRegistry.findResolverFromParent(
                name,
                0,
                offset,
                IRegistry(entry.subregistry),
                entry.resolver
            );
        }
        if (resolver == address(this)) {
            resolver = address(0);
        }
    }

    /// @dev Map an abi-encoded address from `GatewayRequest` to a `NameState`.
    function _nameStateFrom(bytes memory value) internal pure returns (NameState) {
        uint256 i = uint256(bytes32(value));
        return i > uint256(type(NameState).max) ? NameState.NAMECHAIN : NameState(i);
    }

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
