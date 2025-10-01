// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {
    AbstractUniversalResolver,
    IGatewayProvider
} from "@ens/contracts/universalResolver/AbstractUniversalResolver.sol";

import {LibRegistry, IRegistry} from "./libraries/LibRegistry.sol";

contract UniversalResolverV2 is AbstractUniversalResolver {
    IRegistry public immutable ROOT_REGISTRY;

    constructor(
        IRegistry root,
        IGatewayProvider batchGatewayProvider
    ) AbstractUniversalResolver(batchGatewayProvider) {
        ROOT_REGISTRY = root;
    }

    /// @inheritdoc AbstractUniversalResolver
    function findResolver(
        bytes memory name
    ) public view override returns (address resolver, bytes32 node, uint256 offset) {
        (, resolver, node, offset) = LibRegistry.findResolver(ROOT_REGISTRY, name, 0);
    }
}
