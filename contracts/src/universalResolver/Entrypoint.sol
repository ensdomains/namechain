// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {IRegistry} from "../common/registry/interfaces/IRegistry.sol";

import {IEntrypoint} from "./interfaces/IEntrypoint.sol";
import {LibRegistry} from "./libraries/LibRegistry.sol";

contract Entrypoint is ERC165, IEntrypoint {
    IRegistry public immutable REGISTRY;
    bytes32 public immutable NODE;
    bytes public NAME;

    constructor(bytes memory name, IRegistry registry) {
        NAME = name;
        NODE = NameCoder.namehash(name, 0);
        REGISTRY = registry;
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId) || type(IEntrypoint).interfaceId == interfaceId;
    }

    /// @inheritdoc IEntrypoint
    function findRegistries(
        bytes calldata name
    ) external view returns (IRegistry[] memory registries) {
        (bool matched, , , uint256 matchOffset) = NameCoder.matchSuffix(name, 0, NODE);
        if (!matched) {
            revert NameNotIncluded(name, NAME);
        }
        registries = new IRegistry[](1 + NameCoder.countLabels(name, 0));
        registries[NameCoder.countLabels(name, matchOffset)] = REGISTRY;
        LibRegistry.findRegistries(name, 0, registries, 0);
    }
}
