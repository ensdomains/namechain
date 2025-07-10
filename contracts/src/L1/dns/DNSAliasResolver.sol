// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {CCIPReader} from "@ens/contracts/ccipRead/CCIPReader.sol";
import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {NameMatcher} from "../../common/NameMatcher.sol";
import {ResolverProfileRewriter} from "../../common/ResolverProfileRewriter.sol";
import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";
import {IFeatureSupporter} from "@ens/contracts/utils/IFeatureSupporter.sol";
import {ResolverFeatures} from "@ens/contracts/resolvers/ResolverFeatures.sol";
import {IExtendedDNSResolver} from "@ens/contracts/resolvers/profiles/IExtendedDNSResolver.sol";

contract DNSAliasResolver is
    ERC165,
    CCIPReader,
    IFeatureSupporter,
    IExtendedDNSResolver
{
    IUniversalResolver public immutable universalResolver;

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

    /// @dev Rewrite or replace name using context.
    ///      If context is `<old-suffix> <new-suffix>`, rewrite name with new suffix.
    ///      Otherwise, replace name with context.
    function _parseContext(
        bytes calldata name,
        bytes calldata context
    ) internal pure returns (bytes memory newName) {
        uint256 sep = BytesUtils.find(context, 0, context.length, " ");
        if (sep < context.length) {
            bytes memory oldSuffix = NameCoder.encode(string(context[:sep]));
            bytes memory newSuffix = NameCoder.encode(
                string(context[sep + 1:])
            );
            (bool matched, , , uint256 suffixOffset) = NameMatcher.suffix(
                name,
                0,
                NameCoder.namehash(oldSuffix, 0)
            );
            require(matched, "expected suffix match");
            return abi.encodePacked(name[:suffixOffset], newSuffix);
        } else {
            return NameCoder.encode(string(context));
        }
    }
}
