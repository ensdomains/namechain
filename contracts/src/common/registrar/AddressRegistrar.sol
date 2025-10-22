// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {HexUtils} from "@ens/contracts/utils/HexUtils.sol";

import {IPermanentRegistry} from "../registry/interfaces/IPermanentRegistry.sol";
import {IRegistry} from "../registry/interfaces/IRegistry.sol";
import {RegistryRolesLib} from "../registry/libraries/RegistryRolesLib.sol";

contract AddressRegistrar {
    IPermanentRegistry public immutable REGISTRY;

    constructor(IPermanentRegistry registry) {
        REGISTRY = registry;
    }

    function claim(address owner, address resolver) external returns (uint256) {
        return
            REGISTRY.register(
                HexUtils.addressToHex(msg.sender),
                owner,
                IRegistry(address(0)),
                resolver,
                RegistryRolesLib.ROLE_SET_RESOLVER | RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN,
                true
            );
    }
}
