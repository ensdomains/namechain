// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {CCIPReader} from "@ens/contracts/ccipRead/CCIPReader.sol";
import {HexUtils} from "@ens/contracts/utils/HexUtils.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {IRemoteRegistryResolver} from "../eth/IRemoteRegistryResolver.sol";
import {IFeatureSupporter} from "@ens/contracts/utils/IFeatureSupporter.sol";
import {ResolverFeatures} from "@ens/contracts/resolvers/ResolverFeatures.sol";
import {IExtendedDNSResolver} from "@ens/contracts/resolvers/profiles/IExtendedDNSResolver.sol";

contract DNSRemoteRegistryResolver is
    ERC165,
    CCIPReader,
    IFeatureSupporter,
    IExtendedDNSResolver
{
    IRemoteRegistryResolver public immutable remoteRegistryResolver;

    constructor(IRemoteRegistryResolver _remoteRegistryResolver) CCIPReader(0) {
        remoteRegistryResolver = _remoteRegistryResolver;
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

    function resolve(
        bytes calldata name,
        bytes calldata data,
        bytes calldata context
    ) external view returns (bytes memory) {
        (address registry, bytes32 nodeSuffix) = _parseContext(context);
        ccipRead(
            address(remoteRegistryResolver),
            abi.encodeCall(
                IRemoteRegistryResolver.resolveWithRegistry,
                (registry, nodeSuffix, name, data)
            )
        );
    }

    function _parseContext(
        bytes calldata context
    ) internal pure returns (address registry, bytes32 nodeSuffix) {
        require(
            context.length > 43 &&
                context[0] == "0" &&
                context[1] == "x" &&
                context[42] == " ",
            "expected <address> <suffix>"
        );
        bool valid;
        (registry, valid) = HexUtils.hexToAddress(context, 2, 42);
        require(valid, "invalid address");
        nodeSuffix = NameCoder.namehash(
            NameCoder.encode(string(context[43:])),
            0
        );
    }
}
