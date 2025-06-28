// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";
import {CCIPBatcher} from "@ens/contracts/ccipRead/CCIPBatcher.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";
import {ENSIP19, COIN_TYPE_ETH} from "@ens/contracts/utils/ENSIP19.sol";

// resolver profiles
import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";
import {INameResolver} from "@ens/contracts/resolvers/profiles/INameResolver.sol";
import {IAddrResolver} from "@ens/contracts/resolvers/profiles/IAddrResolver.sol";
import {IAddressResolver} from "@ens/contracts/resolvers/profiles/IAddressResolver.sol";
import {IMulticallable} from "@ens/contracts/resolvers/IMulticallable.sol";

// TODO: fix this after merge
// resolver features
import {isFeatureSupported} from "../common/IFeatureSupporter.sol";
import {ResolverFeatures} from "../common/ResolverFeatures.sol";

abstract contract AbstractUniversalResolver is
    IUniversalResolver,
    CCIPBatcher,
    Ownable,
    ERC165
{
    string[] _gateways;

    constructor(address owner, string[] memory gateways) Ownable(owner) {
        _gateways = gateways;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165) returns (bool) {
        return
            type(IUniversalResolver).interfaceId == interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @notice Set the default batch gateways, see: `resolve()` and `reverse()`.
    /// @param gateways The batch gateway URLs.
    function setBatchGateways(string[] memory gateways) external onlyOwner {
        _gateways = gateways;
    }

    /// @notice Get the default batch gateways.
    /// @return The batch gateway URLs.
    function batchGateways() external view returns (string[] memory) {
        return _gateways;
    }

    /// @inheritdoc IUniversalResolver
    function findResolver(
        bytes memory name
    )
        public
        view
        virtual
        returns (address resolver, bytes32 node, uint256 offset);

    /// @dev A valid resolver and its relevant properties.
    struct ResolverInfo {
        bytes name; // dns-encoded name (safe to decode)
        uint256 offset; // byte offset into name used for resolver
        bytes32 node; // namehash(name)
        address resolver;
        bool extended; // IExtendedResolver
    }

    /// @dev Returns a valid resolver for `name` or reverts.
    /// @param name The name to search.
    /// @return info The resolver information.
    function requireResolver(
        bytes memory name
    ) public view returns (ResolverInfo memory info) {
        // https://docs.ens.domains/ensip/10
        (info.resolver, info.node, info.offset) = findResolver(name);
        if (info.resolver == address(0)) {
            revert ResolverNotFound(name);
        } else if (
            ERC165Checker.supportsERC165InterfaceUnchecked(
                info.resolver,
                type(IExtendedResolver).interfaceId
            )
        ) {
            info.extended = true;
        } else if (info.offset != 0) {
            revert ResolverNotFound(name); // immediate resolver requires exact match
        } else if (info.resolver.code.length == 0) {
            revert ResolverNotContract(name, info.resolver);
        }
        info.name = name;
    }

    /// @notice Same as `resolveWithGateways()` but uses default batch gateways.
    function resolve(
        bytes calldata name,
        bytes calldata data
    ) external view returns (bytes memory /*result*/, address /*resolver*/) {
        return resolveWithGateways(name, data, _gateways);
    }

    /// @notice Performs ENS name resolution for the supplied name and resolution data.
    /// @notice Callers should enable EIP-3668.
    /// @dev This function executes over multiple steps (step 1 of 2).
    /// @return result The encoded response for the requested call.
    /// @return resolver The address of the resolver that supplied `result`.
    function resolveWithGateways(
        bytes calldata name,
        bytes calldata data,
        string[] memory gateways
    ) public view returns (bytes memory /*result*/, address /*resolver*/) {
        _callResolver(
            requireResolver(name),
            data,
            gateways,
            this.resolveCallback.selector,
            ""
        );
    }

    /// @dev CCIP-Read callback for `resolveWithGateways()` (step 2 of 2).
    /// @param info The resolver that was called.
    /// @param response The response from the resolver.
    function resolveCallback(
        ResolverInfo calldata info,
        bytes calldata response,
        bytes calldata
    ) external pure returns (bytes memory, address) {
        return (response, info.resolver);
    }

    /// @notice Same as `reverseWithGateways()` but uses default batch gateways.
    function reverse(
        bytes memory lookupAddress,
        uint256 coinType
    ) external view returns (string memory, address, address) {
        return reverseWithGateways(lookupAddress, coinType, _gateways);
    }

    struct ReverseArgs {
        bytes lookupAddress;
        uint256 coinType;
        string[] gateways;
    }

    /// @notice Performs ENS reverse resolution for the supplied address and coin type.
    /// @notice Callers should enable EIP-3668.
    /// @dev This function executes over multiple steps (step 1 of 3).
    /// @param lookupAddress The input address.
    /// @param coinType The coin type.
    /// @param gateways The list of batch gateway URLs to use.
    function reverseWithGateways(
        bytes memory lookupAddress,
        uint256 coinType,
        string[] memory gateways
    ) public view returns (string memory, address /* resolver */, address) {
        // https://docs.ens.domains/ensip/19
        ResolverInfo memory info = requireResolver(
            NameCoder.encode(ENSIP19.reverseName(lookupAddress, coinType)) // reverts EmptyAddress
        );
        _callResolver(
            info,
            abi.encodeCall(INameResolver.name, (info.node)),
            gateways,
            this.reverseNameCallback.selector,
            abi.encode(ReverseArgs(lookupAddress, coinType, gateways))
        );
    }

    /// @dev CCIP-Read callback for `reverseWithGateways()` (step 2 of 3).
    /// @param infoRev The resolver for the reverse name that was called.
    /// @param response The abi-encoded `name()` response.
    /// @param extraData The contextual data passed from `reverseWithGateways()`.
    function reverseNameCallback(
        ResolverInfo calldata infoRev,
        bytes calldata response,
        bytes memory extraData // this cannot be calldata due to "stack too deep"
    ) external view returns (string memory primary, address, address) {
        ReverseArgs memory args = abi.decode(extraData, (ReverseArgs));
        primary = abi.decode(response, (string));
        if (bytes(primary).length == 0) {
            return ("", address(0), infoRev.resolver);
        }
        ResolverInfo memory info = requireResolver(NameCoder.encode(primary));
        _callResolver(
            info,
            args.coinType == COIN_TYPE_ETH
                ? abi.encodeCall(IAddrResolver.addr, (info.node))
                : abi.encodeCall(
                    IAddressResolver.addr,
                    (info.node, args.coinType)
                ),
            args.gateways,
            this.reverseAddressCallback.selector,
            abi.encode(args, primary, infoRev.resolver)
        );
    }

    /// @dev CCIP-Read callback for `reverseNameCallback()` (step 3 of 3).
    ///      Reverts `ReverseAddressMismatch`.
    /// @param info The resolver for the primary name that was called.
    /// @param response The response from the resolver.
    /// @param extraData The contextual data passed from `reverseNameCallback()`.
    /// @return primary The resolved primary name.
    /// @return resolver The resolver address for primary name.
    /// @return reverseResolver The resolver address for the reverse name.
    function reverseAddressCallback(
        ResolverInfo calldata info,
        bytes calldata response,
        bytes calldata extraData
    )
        external
        pure
        returns (
            string memory primary,
            address resolver,
            address reverseResolver
        )
    {
        ReverseArgs memory args;
        (args, primary, reverseResolver) = abi.decode(
            extraData,
            (ReverseArgs, string, address)
        );
        bytes memory primaryAddress;
        if (args.coinType == COIN_TYPE_ETH) {
            address addr = abi.decode(response, (address));
            primaryAddress = abi.encodePacked(addr);
        } else {
            primaryAddress = abi.decode(response, (bytes));
        }
        if (!BytesUtils.equals(args.lookupAddress, primaryAddress)) {
            revert ReverseAddressMismatch(primary, primaryAddress);
        }
        resolver = info.resolver;
    }

    /// @dev Efficiently call a resolver.
    ///      If extended and `RESOLVE_MULTICALL` feature is supported, does a direct call.
    ///      Otherwise, uses the batch gateway.
    /// @param info The resolver to call.
    /// @param call The calldata.
    /// @param gateways The list of batch gateway URLs to use.
    /// @param callbackFunction The function selector to call after resolution.
    /// @param extraData The contextual data passed to `callbackFunction`.
    /// @dev The return type of this function is polymorphic depending on the caller.
    function _callResolver(
        ResolverInfo memory info,
        bytes memory call,
        string[] memory gateways,
        bytes4 callbackFunction,
        bytes memory extraData
    ) internal view {
        if (
            info.extended &&
            isFeatureSupported(
                info.resolver,
                ResolverFeatures.RESOLVE_MULTICALL
            )
        ) {
            ccipRead(
                address(info.resolver),
                abi.encodeCall(IExtendedResolver.resolve, (info.name, call)),
                this.resolveExtendedDirectCallback.selector,
                abi.encode(info, bytes4(call), callbackFunction, extraData)
                // TODO: fix this after merge
                // true
            );
        } else {
            bytes[] memory calls;
            bool multi = bytes4(call) == IMulticallable.multicall.selector;
            if (multi) {
                calls = abi.decode(
                    BytesUtils.substring(call, 4, call.length - 4),
                    (bytes[])
                );
            } else {
                calls = new bytes[](1);
                calls[0] = call;
            }
            if (info.extended) {
                for (uint256 i; i < calls.length; i++) {
                    calls[i] = abi.encodeCall(
                        IExtendedResolver.resolve,
                        (info.name, calls[i])
                    );
                }
            }
            ccipRead(
                address(this),
                abi.encodeCall(
                    this.ccipBatch,
                    // TODO: fix this after merge
                    (_createBatch(info.resolver, calls, gateways))
                ),
                this.resolveBatchCallback.selector,
                abi.encode(info, multi, callbackFunction, extraData)
                // TODO: fix this after merge
                // false
            );
        }
    }

    // TODO: delete this after merge
    function _createBatch(
        address target,
        bytes[] memory calls,
        string[] memory gateways
    ) internal pure returns (Batch memory) {
        Lookup[] memory lookups = new Lookup[](calls.length);
        for (uint256 i; i < calls.length; i++) {
            Lookup memory lu = lookups[i];
            lu.target = target;
            lu.call = calls[i];
        }
        return Batch(lookups, gateways);
    }

    /// @dev CCIP-Read callback for `_callResolver()` from calling the resolver directly.
    function resolveExtendedDirectCallback(
        bytes memory response,
        bytes calldata extraData
    ) external view {
        (
            ResolverInfo memory info,
            bytes4 callSelector,
            bytes4 callbackFunction,
            bytes memory extraData_
        ) = abi.decode(extraData, (ResolverInfo, bytes4, bytes4, bytes));
        if (response.length == 0) {
            response = abi.encodeWithSelector(
                UnsupportedResolverProfile.selector,
                callSelector
            );
        }
        if ((response.length & 31) != 0) {
            revert ResolverError(response);
        }
        response = abi.decode(response, (bytes)); // unwrap resolve()
        ccipRead(
            address(this),
            abi.encodeWithSelector(callbackFunction, info, response, extraData_)
        );
    }

    /// @dev CCIP-Read callback for `_callResolver()` from calling the batch gateway.
    function resolveBatchCallback(
        bytes calldata response,
        bytes calldata extraData
    ) external view {
        Lookup[] memory lookups = abi.decode(response, (Batch)).lookups;
        (
            ResolverInfo memory info,
            bool multi,
            bytes4 callbackFunction,
            bytes memory extraData_
        ) = abi.decode(extraData, (ResolverInfo, bool, bytes4, bytes));
        bytes[] memory m = new bytes[](lookups.length);
        for (uint256 i; i < lookups.length; i++) {
            Lookup memory lu = lookups[i];
            bytes memory v = lu.data;
            if ((lu.flags & FLAGS_ANY_ERROR) == 0 && info.extended) {
                v = abi.decode(v, (bytes)); // unwrap resolve()
            } else if ((lu.flags & FLAG_EMPTY_RESPONSE) != 0) {
                v = abi.encodeWithSelector(
                    UnsupportedResolverProfile.selector,
                    bytes4(v)
                );
            }
            m[i] = v;
        }
        bytes memory answer;
        if (multi) {
            answer = abi.encode(m);
        } else {
            answer = m[0];
            if (
                (lookups[0].flags & (FLAG_EMPTY_RESPONSE | FLAG_CALL_ERROR)) !=
                0 && // resolver-originating error
                bytes4(answer) != UnsupportedResolverProfile.selector // dont wrap
            ) {
                answer = abi.encodeWithSelector(ResolverError.selector, answer);
            }
            if (answer.length & 31 != 0) {
                assembly {
                    revert(add(answer, 32), mload(answer))
                }
            }
        }
        ccipRead(
            address(this),
            abi.encodeWithSelector(callbackFunction, info, answer, extraData_)
        );
    }
}
