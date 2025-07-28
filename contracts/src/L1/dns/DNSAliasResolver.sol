// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {CCIPReader} from "@ens/contracts/ccipRead/CCIPReader.sol";
import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {ResolverProfileRewriter} from "../../common/ResolverProfileRewriter.sol";
import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";
import {IFeatureSupporter} from "@ens/contracts/utils/IFeatureSupporter.sol";
import {ResolverFeatures} from "@ens/contracts/resolvers/ResolverFeatures.sol";
import {IExtendedDNSResolver} from "@ens/contracts/resolvers/profiles/IExtendedDNSResolver.sol";

/// @notice Gasless DNSSEC resolver that forwards to another name.
/// Rewrite: "*.nick.com" + `ENS1 <this> com eth` &rarr; "*.nick.eth"
/// Replace: "nick.com" + `ENS1 <this> nick.eth` &rarr; "nick.eth"
contract DNSAliasResolver is
    ERC165,
    CCIPReader,
    IFeatureSupporter,
    IExtendedDNSResolver
{
    IUniversalResolver public immutable universalResolver;

    /// @dev The `name` did not end with `suffix`.
    /// @param name The DNS-encoded name.
    /// @param suffix THe DNS-encoded suffix.
    error NoSuffixMatch(bytes name, bytes suffix);

    constructor(IUniversalResolver _universalResolver) CCIPReader(0) {
        universalResolver = _universalResolver;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165) returns (bool) {
        return
            type(IExtendedDNSResolver).interfaceId == interfaceId ||
            type(IFeatureSupporter).interfaceId == interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IFeatureSupporter
    function supportsFeature(bytes4 feature) external pure returns (bool) {
        return ResolverFeatures.RESOLVE_MULTICALL == feature;
    }

    /// @dev Resolve the records using the name stored in the context.
    function resolve(
        bytes calldata name,
        bytes calldata data,
        bytes calldata context
    ) external view returns (bytes memory) {
        bytes memory newName = _parseContext(name, context);
        ccipRead(
            address(universalResolver),
            abi.encodeCall(
                IUniversalResolver.resolve,
                (
                    newName,
                    ResolverProfileRewriter.replaceNode(
                        data,
                        NameCoder.namehash(newName, 0)
                    )
                )
            )
        );
    }

    /// @dev Modify `name` using rewrite rule supplied via `context`.
    ///      If context is `<old-suffix> <new-suffix>`, rewrite name with new suffix.
    ///      Otherwise, replace name with context.
	/// @param name The DNS-encoded name.
	/// @param context The rewrite rule.
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
