// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {CCIPReader} from "@ens/contracts/ccipRead/CCIPReader.sol";
import {HexUtils} from "@ens/contracts/utils/HexUtils.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {IRegistryResolver} from "../../common/IRegistryResolver.sol";
import {IFeatureSupporter} from "@ens/contracts/utils/IFeatureSupporter.sol";
import {ResolverFeatures} from "@ens/contracts/resolvers/ResolverFeatures.sol";
import {IExtendedDNSResolver} from "@ens/contracts/resolvers/profiles/IExtendedDNSResolver.sol";

/// @notice Gasless DNSSEC resolver that continues resolution on Namechain (or any remote registry).
///
/// Format: `ENS1 <this> <context>`
///
/// 1. Continue: `<parentRegistry> <suffix>`
///    eg. "*.nick.com" + `ENS1 <this> 0x1234 com" &rarr; 0x1234 w/["nick", ...]
///
contract DNSRegistryResolver is
    ERC165,
    CCIPReader,
    IFeatureSupporter,
    IExtendedDNSResolver
{
    IRegistryResolver public immutable registryResolver;

    /// @notice The DNS context was invalid.
    /// @dev Error selector: `0x206fb1e7`
    error InvalidContext(bytes context);

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
    function supportsFeature(bytes4 feature) external view returns (bool) {
        return
            ResolverFeatures.RESOLVE_MULTICALL == feature &&
            ERC165Checker.supportsInterface(
                address(registryResolver),
                type(IFeatureSupporter).interfaceId
            );
    }

    /// @dev Resolve the records using `registryResolver` starting from `parentRegistry` for `name` before `nodeSuffix`.
    function resolve(
        bytes calldata name,
        bytes calldata data,
        bytes calldata context
    ) external view returns (bytes memory) {
        (address parentRegistry, bytes32 nodeSuffix) = _parseContext(context);
        ccipRead(
            address(registryResolver),
            abi.encodeCall(
                IRegistryResolver.resolveWithRegistry,
                (parentRegistry, nodeSuffix, name, data)
            )
        );
    }

    /// @dev Parse context string.
    /// @param context The formatted context string.
    /// @return parentRegistry The parent registry to start traversal.
    /// @return nodeSuffix The suffix to drop from the name before resolving.
    function _parseContext(
        bytes calldata context
    ) internal pure returns (address parentRegistry, bytes32 nodeSuffix) {
        if (
            context.length < 43 ||
            context[0] != "0" ||
            context[1] != "x" ||
            context[42] != " "
        ) {
            revert InvalidContext(context); // expected "<address> <suffix>"
        }
        bool valid;
        (parentRegistry, valid) = HexUtils.hexToAddress(context, 2, 42);
        if (!valid) {
            revert InvalidContext(context); // invalid address
        }
        nodeSuffix = NameCoder.namehash(
            NameCoder.encode(string(context[43:])),
            0
        );
    }
}
