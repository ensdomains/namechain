// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {CCIPReader} from "@ens/contracts/ccipRead/CCIPReader.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
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
        bytes calldata,
        bytes calldata data,
        bytes calldata context
    ) external view returns (bytes memory) {
        bytes memory name = NameCoder.encode(string(context));
        ccipRead(
            address(universalResolver),
            abi.encodeCall(
                IUniversalResolver.resolve,
                (
                    name,
                    ResolverProfileRewriter.replaceNode(
                        data,
                        NameCoder.namehash(name, 0)
                    )
                )
            )
        );
    }
}
