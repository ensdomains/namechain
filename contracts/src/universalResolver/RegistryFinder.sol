// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

import {IRegistry} from "../common/registry/interfaces/IRegistry.sol";

import {LibRegistry} from "./libraries/LibRegistry.sol";

contract RegistryFinder {
    IRegistry public immutable REGISTRY;
    bytes32 private immutable _NODE;

    bytes public baseName;

    error NameNotSubdomain(bytes name, bytes baseName);

    constructor(IRegistry registry, bytes memory name) {
        REGISTRY = registry;
        _NODE = NameCoder.namehash(name, 0);
        baseName = name;
    }

    /// @notice Find all registries in the ancestry of `name` back to `baseName`.
    ///
    /// For baseName = "eth",
    /// * `findRegistries("") => revert NameNotSubdomain("", "eth")
    /// * `findRegistries("eth") = [<eth>, null]`
    /// * `findRegistries("nick.eth") = [<nick>, <eth>, null]`
    /// * `findRegistries("sub.nick.eth") = [null, <nick>, <eth>, null]`
    ///
    /// @param name The DNS-encoded name.
    ///
    /// @return registries Array of registries in label-order.
    function findRegistries(
        bytes calldata name
    ) external view returns (IRegistry[] memory registries) {
        (bool matched, , , uint256 matchOffset) = NameCoder.matchSuffix(name, 0, _NODE);
        if (!matched) {
            revert NameNotSubdomain(name, baseName);
        }
        registries = new IRegistry[](1 + NameCoder.countLabels(name, 0));
        registries[NameCoder.countLabels(name, matchOffset)] = REGISTRY;
        LibRegistry.buildAncestory(name, 0, registries, 0);
    }
}
