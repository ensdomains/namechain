// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {AbstractUniversalResolver} from "./AbstractUniversalResolver.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {ResolverFinder} from "./ResolverFinder.sol";

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
        node = NameCoder.namehash(name, 0);
        (, , resolver, offset) = ResolverFinder.findResolver(
            rootRegistry,
            name,
            0
        );
    }

    /// @notice Finds the nearest registry for `name`.
    /// @param name The name to find.
    /// @return registry The nearest registry for `name`.
    /// @return exact True if the registry is an exact match for `name`.
    function getRegistry(
        bytes memory name
    ) external view returns (IRegistry registry, bool exact) {
        (registry, exact, , ) = ResolverFinder.findResolver(
            rootRegistry,
            name,
            0
        );
    }

    /// @notice Finds the registry responsible for `name`.
    /// @param name The name to find.
    /// @return registry The registry responsible for `name` or null.
    /// @return label The leading label if `registry` exists or null.
    function getParentRegistry(
        bytes calldata name
    ) external view returns (IRegistry registry, string memory label) {
        (bytes32 labelHash, uint256 offset) = NameCoder.readLabel(name, 0);
        if (labelHash != bytes32(0)) {
            (IRegistry parent, bool exact, , ) = ResolverFinder.findResolver(
                rootRegistry,
                name,
                offset
            );
            if (exact) {
                registry = parent;
                label = string(name[1:offset]);
            }
        }
    }
}
