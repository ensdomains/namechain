// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistry, IRegistryMetadata, IRegistryDatastore} from "../RootRegistry.sol";
import {UserRegistry} from "../UserRegistry.sol";

contract MockUserRegistry is UserRegistry {
    constructor(
        IRegistry _parent,
        string memory _label,
        IRegistryDatastore _datastore
    )
        UserRegistry(_parent, _label, _datastore, IRegistryMetadata(address(0)))
    {}
    function setResolver(uint256 tokenId, address resolver) external {
        datastore.setResolver(tokenId, resolver, 0);
    }
}
