// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {
    IEnhancedAccessControl
} from "../../common/access-control/interfaces/IEnhancedAccessControl.sol";
import {IPermissionedRegistry} from "../../common/registry/interfaces/IPermissionedRegistry.sol";
import {IRegistry} from "../../common/registry/interfaces/IRegistry.sol";
import {IRegistryDatastore} from "../../common/registry/interfaces/IRegistryDatastore.sol";
import {RegistryRolesLib} from "../../common/registry/libraries/RegistryRolesLib.sol";
import {HCAEquivalence} from "../hca/HCAEquivalence.sol";
import {IHCAFactoryBasic} from "../hca/interfaces/IHCAFactoryBasic.sol";

struct BatchRegistrarName {
    string label;
    address owner;
    IRegistry registry;
    address resolver;
    uint256 roleBitmap;
    uint64 expires;
}

contract BatchRegistrar is HCAEquivalence {
    constructor(IHCAFactoryBasic hcaFactory) HCAEquivalence(hcaFactory) {}

    function batchRegister(
        IPermissionedRegistry registry,
        BatchRegistrarName[] calldata names
    ) external {
        address sender = _msgSenderWithHcaEquivalence();
        if (!registry.hasRootRoles(RegistryRolesLib.ROLE_REGISTRAR, sender)) {
            revert IEnhancedAccessControl.EACUnauthorizedAccountRoles(
                0,
                RegistryRolesLib.ROLE_REGISTRAR,
                sender
            );
        }
        for (uint256 i; i < names.length; ++i) {
            BatchRegistrarName calldata name = names[i];

            // Check if name is already registered
            (uint256 tokenId, IRegistryDatastore.Entry memory entry) = registry.getNameData(
                name.label
            );

            // If name has never been registered or has expired, register it
            if (entry.expiry == 0 || entry.expiry <= block.timestamp) {
                registry.register(
                    name.label,
                    name.owner,
                    name.registry,
                    name.resolver,
                    name.roleBitmap,
                    name.expires
                );
            } else {
                // Name is still valid - renew if new expiry is later
                if (name.expires > entry.expiry) {
                    registry.renew(tokenId, name.expires);
                }
                // If expires <= currentExpiry, skip (no action needed)
            }
        }
    }
}
