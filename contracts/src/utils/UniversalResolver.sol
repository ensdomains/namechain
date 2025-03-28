// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";
import {CCIPBatcher} from "@ens/contracts/ccipRead/CCIPBatcher.sol";
import {IRegistry} from "../registry/IRegistry.sol";
import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";
import {INameResolver} from "@ens/contracts/resolvers/profiles/INameResolver.sol";
import {IAddrResolver} from "@ens/contracts/resolvers/profiles/IAddrResolver.sol";
import {IAddressResolver} from "@ens/contracts/resolvers/profiles/IAddressResolver.sol";
import {IMulticallable} from "@ens/contracts/resolvers/IMulticallable.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";
import {ENSIP19, COIN_TYPE_ETH} from "@ens/contracts/utils/ENSIP19.sol";

contract UniversalResolver is IUniversalResolver, CCIPBatcher, Ownable, ERC165 {
    IRegistry public immutable rootRegistry;
    string[] public batchGateways;

    constructor(IRegistry root, string[] memory gateways) Ownable(msg.sender) {
        rootRegistry = root;
        batchGateways = gateways;
    }

    function supportsInterface(
        bytes4 interfaceID
    ) public view virtual override(ERC165) returns (bool) {
        return
            super.supportsInterface(interfaceID) &&
            type(IUniversalResolver).interfaceId == interfaceID;
    }

    /// @dev Set the default batch gateways, see: `resolve()` and `reverse()`.
    /// @param gateways The list of batch gateway URLs to use as default.
    function setBatchGateways(string[] memory gateways) external onlyOwner {
        batchGateways = gateways;
    }

    /// @dev Finds the registry responsible for a name.
    ///      If there is no registry for the full name, the registry for the longest
    ///      extant suffix is returned instead.
    /// @param name The name to look up.
    /// @return reg A registry responsible for the name.
    /// @return exact A boolean that is true if the registry is an exact match for `name`.
    function getRegistry(
        bytes memory name
    ) public view returns (IRegistry reg, bool exact) {
        uint256 len = uint8(name[0]);
        if (len == 0) {
            return (rootRegistry, true);
        }
        (reg, exact) = getRegistry(
            BytesUtils.substring(name, 1 + len, name.length - len - 1)
        );
        if (!exact) {
            return (reg, false);
        }
        string memory label = string(BytesUtils.substring(name, 1, len));
        IRegistry sub = reg.getSubregistry(label);
        if (sub == IRegistry(address(0))) {
            return (reg, false);
        }
        return (sub, true);
    }

    /// @dev Finds the resolver responsible for a name, or `address(0)` if none.
    /// @param name The name to find a resolver for.
    /// @return reg A registry responsible for the name.
    /// @return exact A boolean that is true if the registry is an exact match for `name`.
    /// @return resolver The resolver responsible for this name, or `address(0)` if none.
    function getResolver(
        bytes memory name
    ) public view returns (IRegistry reg, bool exact, address resolver) {
        (reg, exact) = getRegistry(name);
        uint8 len = uint8(name[0]);
        string memory label = string(BytesUtils.substring(name, 1, len));
        resolver = reg.getResolver(label);
    }

    // @dev A valid resolver and its relevant properties.
    struct ResolverInfo {
        bytes name; // dns-encoded name (safe to decode)
        bool exact; // uint256 offset; // byte offset into name used for resolver
        bytes32 node; // namehash(name)
        IRegistry registry;
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
        (info.registry, info.exact, info.resolver) = getResolver(name);
        if (info.resolver == address(0)) {
            revert ResolverNotFound(name);
        } else if (
            ERC165Checker.supportsERC165InterfaceUnchecked(
                info.resolver,
                type(IExtendedResolver).interfaceId
            )
        ) {
            info.extended = true;
        } else if (!info.exact) {
            revert ResolverNotFound(name); // immediate resolver requires exact match
        } else if (info.resolver.code.length == 0) {
            revert ResolverNotContract(name, info.resolver);
        }
        info.name = name;
        info.node = NameCoder.namehash(name, 0);
    }

    /// @notice Same as `resolveWithGateways()` but uses default batch gateways.
    function resolve(
        bytes calldata name,
        bytes calldata data
    ) external view returns (bytes memory /*result*/, address /*resolver*/) {
        return resolveWithGateways(name, data, batchGateways);
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
        bool multi = bytes4(data) == IMulticallable.multicall.selector;
        _resolveBatch(
            requireResolver(name),
            multi ? abi.decode(data[4:], (bytes[])) : _oneCall(data),
            gateways,
            this.resolveCallback.selector,
            abi.encode(multi)
        );
    }

    /// @dev CCIP-Read callback for `resolveWithGateways()` (step 2 of 2).
    /// @param info The resolver that was called.
    /// @param lookups The lookups corresponding to the requested call.
    /// @param extraData The contextual data passed from `resolveWithGateways()`.
    /// @return result The encoded response for the requested call.
    /// @return resolver The address of the resolver that supplied `result`.
    function resolveCallback(
        ResolverInfo calldata info,
        Lookup[] calldata lookups,
        bytes calldata extraData
    ) external pure returns (bytes memory result, address resolver) {
        bool multi = abi.decode(extraData, (bool));
        if (multi) {
            bytes[] memory m = new bytes[](lookups.length);
            for (uint256 i; i < lookups.length; i++) {
                Lookup memory lu = lookups[i];
                if ((lu.flags & FLAG_EMPTY_RESPONSE) == 0) {
                    m[i] = lookups[i].data;
                }
            }
            result = abi.encode(m);
        } else {
            result = _requireResponse(lookups[0]);
        }
        resolver = info.resolver;
    }

    /// @notice Same as `reverseWithGateways()` but uses default batch gateways.
    function reverse(
        bytes memory encodedAddress,
        uint256 coinType
    ) external view returns (string memory, address /* resolver */, address) {
        return reverseWithGateways(encodedAddress, coinType, batchGateways);
    }

    struct ReverseArgs {
        bytes encodedAddress;
        uint256 coinType;
        string[] gateways;
    }

    /// @notice Performs ENS reverse resolution for the supplied address and coin type.
    /// @notice Callers should enable EIP-3668.
    /// @dev This function executes over multiple steps (step 1 of 3).
    /// @param encodedAddress The input address.
    /// @param coinType The coin type.
    /// @param gateways The list of batch gateway URLs to use.
    function reverseWithGateways(
        bytes memory encodedAddress,
        uint256 coinType,
        string[] memory gateways
    ) public view returns (string memory, address /* resolver */, address) {
        // https://docs.ens.domains/ensip/19
        ResolverInfo memory info = requireResolver(
            NameCoder.encode(ENSIP19.reverseName(encodedAddress, coinType)) // reverts EmptyAddress
        );
        _resolveBatch(
            info,
            _oneCall(abi.encodeCall(INameResolver.name, (info.node))),
            gateways,
            this.reverseNameCallback.selector,
            abi.encode(ReverseArgs(encodedAddress, coinType, gateways))
        );
    }

    /// @dev CCIP-Read callback for `reverseWithGateways()` (step 2 of 3).
    /// @param infoRev The resolver for the reverse name that was called.
    /// @param lookups The lookups corresponding to the calls: `[name()]`.
    /// @param extraData The contextual data passed from `reverseWithGateways()`.
    function reverseNameCallback(
        ResolverInfo calldata infoRev,
        Lookup[] calldata lookups,
        bytes memory extraData // this cannot be calldata due to "stack too deep"
    ) external view returns (string memory primary, address, address) {
        ReverseArgs memory args = abi.decode(extraData, (ReverseArgs));
        primary = abi.decode(_requireResponse(lookups[0]), (string));
        if (bytes(primary).length == 0) {
            return ("", address(0), infoRev.resolver);
        }
        ResolverInfo memory info = requireResolver(NameCoder.encode(primary));
        _resolveBatch(
            info,
            _oneCall(
                args.coinType == COIN_TYPE_ETH
                    ? abi.encodeCall(IAddrResolver.addr, (info.node))
                    : abi.encodeCall(
                        IAddressResolver.addr,
                        (info.node, args.coinType)
                    )
            ),
            args.gateways,
            this.reverseAddressCallback.selector,
            abi.encode(args.encodedAddress, primary, infoRev.resolver)
        );
    }

    /// @dev CCIP-Read callback for `reverseNameCallback()` (step 3 of 3).
    ///      Reverts `ReverseAddressMismatch`.
    /// @param info The resolver for the primary name that was called.
    /// @param lookups The lookups corresponding to the calls: `[addr()]`.
    /// @param extraData The contextual data passed from `reverseNameCallback()`.
    /// @return primary The resolved primary name.
    /// @return resolver The resolver address for primary name.
    /// @return reverseResolver The resolver address for the reverse name.
    function reverseAddressCallback(
        ResolverInfo calldata info,
        Lookup[] calldata lookups,
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
        bytes memory reverseAddress;
        (reverseAddress, primary, reverseResolver) = abi.decode(
            extraData,
            (bytes, string, address)
        );
        bytes memory v = _requireResponse(lookups[0]);
        bytes memory primaryAddress;
        bytes4 selector = bytes4(lookups[0].call);
        if (selector == IAddrResolver.addr.selector) {
            address addr = abi.decode(v, (address));
            primaryAddress = abi.encodePacked(addr);
        } else if (selector == IAddressResolver.addr.selector) {
            primaryAddress = abi.decode(v, (bytes));
        }
        if (!BytesUtils.equals(reverseAddress, primaryAddress)) {
            revert ReverseAddressMismatch(primary, primaryAddress);
        }
        resolver = info.resolver;
    }

    /// @dev Perform multiple resolver calls in parallel using batch gateway.
    /// @param info The resolver to call.
    /// @param calls The list of resolver calldata, eg. `[addr(), text()]`.
    /// @param gateways The list of batch gateway URLs to use.
    /// @param callbackFunction The function selector to call after resolution.
    /// @param extraData The contextual data passed to `callbackFunction`.
    /// @dev The return type of this function is polymorphic depending on the caller.
    function _resolveBatch(
        ResolverInfo memory info,
        bytes[] memory calls,
        string[] memory gateways,
        bytes4 callbackFunction,
        bytes memory extraData
    ) internal view {
        Batch memory batch = Batch(new Lookup[](calls.length), gateways);
        for (uint256 i; i < calls.length; i++) {
            Lookup memory lu = batch.lookups[i];
            lu.target = info.resolver;
            lu.call = info.extended
                ? abi.encodeCall(
                    IExtendedResolver.resolve,
                    (info.name, calls[i])
                )
                : calls[i];
        }
        ccipRead(
            address(this),
            abi.encodeCall(this.ccipBatch, (batch)),
            this.resolveBatchCallback.selector,
            abi.encode(info, callbackFunction, extraData)
        );
    }

    /// @dev CCIP-Read callback for `_resolveBatch()`.
    /// @param response The response data from `CCIPBatcher`.
    /// @param extraData The contextual data from `_resolveBatch()`.
    function resolveBatchCallback(
        bytes calldata response,
        bytes calldata extraData
    ) external view {
        Batch memory batch = abi.decode(response, (Batch));
        (
            ResolverInfo memory info,
            bytes4 callbackFunction_,
            bytes memory extraData_
        ) = abi.decode(extraData, (ResolverInfo, bytes4, bytes));
        if (info.extended) {
            for (uint256 i; i < batch.lookups.length; i++) {
                Lookup memory lu = batch.lookups[i];
                lu.call = _unwrapResolve(lu.call);
                if ((lu.flags & FLAGS_ANY_ERROR) == 0) {
                    lu.data = abi.decode(lu.data, (bytes));
                }
            }
        }
        ccipRead(
            address(this),
            abi.encodeWithSelector(
                callbackFunction_,
                info,
                batch.lookups,
                extraData_
            )
        );
    }

    /// @dev Extract `data` from `resolve(bytes, bytes data)` calldata.
    /// @param v The `resolve(bytes, bytes data)` calldata.
    /// @return data The inner `bytes data` argument.
    function _unwrapResolve(
        bytes memory v
    ) internal pure returns (bytes memory data) {
        // resolve(bytes name, bytes data):      | <== offset starts here
        // => uint256(length) + bytes4(selector) | offset(name) + offset(data)
        //           32       +        4         |      32
        assembly {
            data := add(v, 36) // location of offset start
            data := add(data, mload(add(data, 32))) // += offset(data)
        }
    }

    /// @dev Extract `data` from a lookup or revert an appropriate error.
    ///      Reverts if the `data` is not a successful response.
    /// @param lu The lookup to extract from.
    /// @return v The successful response (always 32+ bytes).
    function _requireResponse(
        Lookup memory lu
    ) internal pure returns (bytes memory v) {
        v = lu.data;
        if ((lu.flags & FLAG_BATCH_ERROR) != 0) {
            assembly {
                revert(add(v, 32), mload(v)) // HttpError or Error
            }
        } else if ((lu.flags & FLAG_CALL_ERROR) != 0) {
            if (bytes4(v) == UnsupportedResolverProfile.selector) {
                assembly {
                    revert(add(v, 32), mload(v))
                }
            }
            revert ResolverError(v); // any error from Resolver
        } else if ((lu.flags & FLAG_EMPTY_RESPONSE) != 0) {
            revert UnsupportedResolverProfile(bytes4(v)); // initial call or callback was unimplemented
        }
    }

    /// @dev Create an array with one `call`.
    /// @param call The single calldata.
    /// @return calls The one-element calldata array, eg. `[call]`.
    function _oneCall(
        bytes memory call
    ) internal pure returns (bytes[] memory calls) {
        calls = new bytes[](1);
        calls[0] = call;
    }
}
