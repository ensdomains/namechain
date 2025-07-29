// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {AbstractUniversalResolver} from "./AbstractUniversalResolver.sol";
import {RegistryUtils, IRegistry} from "./RegistryUtils.sol";

contract UniversalResolverV2 is AbstractUniversalResolver {
    IRegistry public immutable rootRegistry;

    constructor(
        IRegistry root,
        string[] memory gateways
    ) AbstractUniversalResolver(msg.sender, gateways) {
        rootRegistry = root;
    }

    /// @inheritdoc AbstractUniversalResolver
    function findResolver(
        bytes memory name
    )
        public
        view
        override
        returns (address resolver, bytes32 node, uint256 offset)
    {
        (, resolver, node, offset) = RegistryUtils.findResolver(
            rootRegistry,
            name,
            0
        );
    }
}
