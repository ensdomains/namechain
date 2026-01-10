// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IGatewayProvider} from "@ens/contracts/ccipRead/IGatewayProvider.sol";
import {
    AbstractUniversalResolver
} from "@ens/contracts/universalResolver/AbstractUniversalResolver.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {IRegistry} from "../common/registry/interfaces/IRegistry.sol";

import {Entrypoint} from "./Entrypoint.sol";
import {LibRegistry} from "./libraries/LibRegistry.sol";

contract UniversalResolverV2 is AbstractUniversalResolver, Entrypoint {
    constructor(
        IRegistry rootRegistry,
        IGatewayProvider batchGatewayProvider
    ) Entrypoint(hex"00", rootRegistry) AbstractUniversalResolver(batchGatewayProvider) {}

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(AbstractUniversalResolver, Entrypoint) returns (bool) {
        return
            AbstractUniversalResolver.supportsInterface(interfaceId) ||
            Entrypoint.supportsInterface(interfaceId);
    }

    /// @inheritdoc AbstractUniversalResolver
    function findResolver(
        bytes memory name
    ) public view override returns (address resolver, bytes32 node, uint256 offset) {
        (, resolver, node, offset) = LibRegistry.findResolver(REGISTRY, name, 0);
    }
}
