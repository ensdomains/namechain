// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IPermissionedRegistry} from "../../common/registry/interfaces/IPermissionedRegistry.sol";
import {IRegistry} from "../../common/registry/interfaces/IRegistry.sol";
import {IRegistryDatastore} from "../../common/registry/interfaces/IRegistryDatastore.sol";

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

            // Check if name is already registered
            (uint256 tokenId, IRegistryDatastore.Entry memory entry) = ETH_REGISTRY.getNameData(
                name.label
            );

            // If name has never been registered or has expired, register it
            if (entry.expiry == 0 || entry.expiry <= block.timestamp) {
                ETH_REGISTRY.register(
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
                    ETH_REGISTRY.renew(tokenId, name.expires);
                }
                // If expires <= currentExpiry, skip (no action needed)
            }
        }
    }
}
