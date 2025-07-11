// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {CCIPReader} from "@ens/contracts/ccipRead/CCIPReader.sol";
import {HexUtils} from "@ens/contracts/utils/HexUtils.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {IRegistryResolver} from "../../common/IRegistryResolver.sol";
import {IFeatureSupporter} from "@ens/contracts/utils/IFeatureSupporter.sol";
import {ResolverFeatures} from "@ens/contracts/resolvers/ResolverFeatures.sol";
import {IExtendedDNSResolver} from "@ens/contracts/resolvers/profiles/IExtendedDNSResolver.sol";

/// @title DNSRegistryResolver
/// @notice Gasless DNSSEC resolver that continues resolution on Namechain (or any remote registry).
/// "*.nick.com" + `ENS1 <this> <parentRegistry> com" &rarr; parentRegistry w/["nick", ...]
contract DNSRegistryResolver is
    ERC165,
    CCIPReader,
    IFeatureSupporter,
    IExtendedDNSResolver
{
    IRegistryResolver public immutable registryResolver;

    constructor(IRegistryResolver _registryResolver) CCIPReader(0) {
        registryResolver = _registryResolver;
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

    /// @dev Resolve the records using `registryResolver`.
    function resolve(
        bytes calldata name,
        bytes calldata data,
        bytes calldata context
    ) external view returns (bytes memory) {
        (address registry, bytes32 nodeSuffix) = _parseContext(context);
        ccipRead(
            address(registryResolver),
            abi.encodeCall(
                IRegistryResolver.resolveWithRegistry,
                (registry, nodeSuffix, name, data)
            )
        );
    }

    function _parseContext(
        bytes calldata context
    ) internal pure returns (address registry, bytes32 nodeSuffix) {
        require(
            context.length >= 43 &&
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
