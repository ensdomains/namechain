// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IPermissionedRegistry} from "../../common/registry/interfaces/IPermissionedRegistry.sol";
import {IRegistry} from "../../common/registry/interfaces/IRegistry.sol";

struct BatchRegistrarName {
    string label;
    address owner;
    IRegistry registry;
    address resolver;
    uint256 roleBitmap;
    uint64 expires;
}

contract BatchRegistrar {
    IPermissionedRegistry public immutable ETH_REGISTRY;

    constructor(IPermissionedRegistry ethRegistry_) {
        ETH_REGISTRY = ethRegistry_;
    }

    function batchRegister(BatchRegistrarName[] calldata names) external {
        for (uint256 i = 0; i < names.length; i++) {
            BatchRegistrarName calldata name = names[i];
            ETH_REGISTRY.register(
                name.label,
                name.owner,
                name.registry,
                name.resolver,
                name.roleBitmap,
                name.expires
            );
        }
    }
}
