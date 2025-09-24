// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {CCIPReader} from "@ens/contracts/ccipRead/CCIPReader.sol";
import {IGatewayProvider} from "@ens/contracts/ccipRead/IGatewayProvider.sol";
import {
    IExtendedDNSResolver
} from "@ens/contracts/resolvers/profiles/IExtendedDNSResolver.sol";
import {ResolverFeatures} from "@ens/contracts/resolvers/ResolverFeatures.sol";
import {
    ResolverCaller
} from "@ens/contracts/universalResolver/ResolverCaller.sol";
import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";
import {IERC7996} from "@ens/contracts/utils/IERC7996.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {
    ResolverProfileRewriter
} from "./../../common/ResolverProfileRewriter.sol";
import {
    RegistryUtils,
    IRegistry
} from "./../../universalResolver/RegistryUtils.sol";

/// @notice Gasless DNSSEC resolver that forwards to another name.
///
///         Format: `ENS1 <this> <context>`
///
///         1. Rewrite: `context = <oldSuffix> <newSuffix>`
///            eg. `*.nick.com` + `ENS1 <this> com base.eth` &rarr; `*.nick.base.eth`
///         2. Replace: `context = <newName>`
///            eg. `notdot.net` + `ENS1 <this> nick.eth` &rarr; `nick.eth`
///
contract DNSAliasResolver is
    ERC165,
    ResolverCaller,
    IERC7996,
    IExtendedDNSResolver
{
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    IRegistry public immutable ROOT_REGISTRY;

    /// @dev Shared batch gateway provider.
    IGatewayProvider public immutable BATCH_GATEWAY_PROVIDER;

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    /// @dev The `name` did not end with `suffix`.
    /// @param name The DNS-encoded name.
    /// @param suffix THe DNS-encoded suffix.
    error NoSuffixMatch(bytes name, bytes suffix);

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        IRegistry rootRegistry_,
        IGatewayProvider batchGatewayProvider_
    ) CCIPReader(DEFAULT_UNSAFE_CALL_GAS) {
        ROOT_REGISTRY = rootRegistry_;
        BATCH_GATEWAY_PROVIDER = batchGatewayProvider_;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165) returns (bool) {
        return
            type(IExtendedDNSResolver).interfaceId == interfaceId ||
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

    /// @dev Resolve the records after applying rewrite rule.
    function resolve(
        bytes calldata name,
        bytes calldata data,
        bytes calldata context
    ) external view returns (bytes memory) {
        bytes memory newName = _parseContext(name, context);
        (, address resolver, bytes32 node, ) = RegistryUtils.findResolver(
            ROOT_REGISTRY,
            newName,
            0
        );
        callResolver(
            resolver,
            newName,
            ResolverProfileRewriter.replaceNode(data, node),
            BATCH_GATEWAY_PROVIDER.gateways()
        );
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    /// @dev Modify `name` using rewrite rule in `context`.
    ///
    /// @param name The DNS-encoded name.
    /// @param context The rewrite rule.
    ///
    /// @return newName The modified DNS-encoded name.
    function _parseContext(
        bytes calldata name,
        bytes calldata context
    ) internal pure returns (bytes memory newName) {
        uint256 sep = BytesUtils.find(context, 0, context.length, " ");
        if (sep < context.length) {
            bytes memory oldSuffix = NameCoder.encode(string(context[:sep]));
            (bool matched, , , uint256 offset) = NameCoder.matchSuffix(
                name,
                0,
                NameCoder.namehash(oldSuffix, 0)
            );
            if (!matched) {
                revert NoSuffixMatch(name, oldSuffix);
            }
            bytes memory newSuffix = NameCoder.encode(
                string(context[sep + 1:])
            );
            return abi.encodePacked(name[:offset], newSuffix); // rewrite
        } else {
            return NameCoder.encode(string(context)); // replace
        }
    }
}
