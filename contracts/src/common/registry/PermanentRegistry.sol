// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {EnhancedAccessControl} from "../access-control/EnhancedAccessControl.sol";
import {LibLabel} from "../utils/LibLabel.sol";

import {IPermanentRegistry} from "./interfaces/IPermanentRegistry.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {IRegistryDatastore} from "./interfaces/IRegistryDatastore.sol";
import {IRegistryMetadata} from "./interfaces/IRegistryMetadata.sol";
import {RegistryRolesLib} from "./libraries/RegistryRolesLib.sol";
import {MetadataMixin} from "./MetadataMixin.sol";

contract PermanentRegistry is IPermanentRegistry, EnhancedAccessControl, MetadataMixin {
    IRegistryDatastore public immutable DATASTORE;

    event SubregistryUpdate(uint256 indexed id, IRegistry subregistry);
    event ResolverUpdate(uint256 indexed id, address resolver);

    constructor(
        address owner,
        uint256 ownerRoles,
        IRegistryDatastore datastore,
        IRegistryMetadata metadata
    ) MetadataMixin(metadata) {
        DATASTORE = datastore;
        _grantRoles(ROOT_RESOURCE, ownerRoles, owner, false);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(EnhancedAccessControl, IERC165) returns (bool) {
        return
            interfaceId == type(IPermanentRegistry).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function register(
        string calldata label,
        address operator,
        IRegistry subregistry,
        address resolver,
        uint256 roleBitmap,
        bool reset
    ) external onlyRootRoles(RegistryRolesLib.ROLE_REGISTRAR) returns (uint256 id) {
        id = LibLabel.labelToCanonicalId(label);
        IRegistryDatastore.Entry memory entry = DATASTORE.getEntry(address(this), id);
        if (reset) {
            ++entry.eacVersionId;
        }
        id |= entry.eacVersionId;
        entry.subregistry = address(subregistry);
        entry.resolver = resolver;
        DATASTORE.setEntry(id, entry);
        if (_grantRoles(id, roleBitmap, operator, false)) {
            emit NewSubname(id, label);
        }
        emit SubregistryUpdate(id, subregistry);
        emit ResolverUpdate(id, resolver);
    }

    function setSubregistry(string calldata label, IRegistry subregistry) external {
        uint256 id = LibLabel.labelToCanonicalId(label);
        IRegistryDatastore.Entry memory entry = DATASTORE.getEntry(address(this), id);
        id |= entry.eacVersionId;
        _checkRoles(id, RegistryRolesLib.ROLE_SET_SUBREGISTRY, _msgSender());
        DATASTORE.setSubregistry(id, address(subregistry));
        emit SubregistryUpdate(id, subregistry);
    }

    function setResolver(string calldata label, address resolver) external {
        uint256 id = LibLabel.labelToCanonicalId(label);
        IRegistryDatastore.Entry memory entry = DATASTORE.getEntry(address(this), id);
        id |= entry.eacVersionId;
        _checkRoles(id, RegistryRolesLib.ROLE_SET_RESOLVER, _msgSender());
        DATASTORE.setResolver(id, resolver);
        emit ResolverUpdate(id, resolver);
    }

    function getSubregistry(string calldata label) external view virtual returns (IRegistry) {
        return
            IRegistry(
                DATASTORE.getEntry(address(this), LibLabel.labelToCanonicalId(label)).subregistry
            );
    }

    function getResolver(string calldata label) external view virtual returns (address) {
        return DATASTORE.getEntry(address(this), LibLabel.labelToCanonicalId(label)).resolver;
    }
}
