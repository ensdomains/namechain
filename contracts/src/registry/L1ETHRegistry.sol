// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IL1EjectionController} from "../controller/IL1EjectionController.sol";
import {ERC1155Singleton} from "./ERC1155Singleton.sol";
import {IERC1155Singleton} from "./IERC1155Singleton.sol";
import {IRegistry} from "./IRegistry.sol";
import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {BaseRegistry} from "./BaseRegistry.sol";
import {PermissionedRegistry} from "./PermissionedRegistry.sol";
import {IRegistryMetadata} from "./IRegistryMetadata.sol";

/**
 * @title L1ETHRegistry
 * @dev L1 contract for .eth that holds ejected .eth names only.
 * Unlike the L2 ETHRegistry, this registry does not handle new registrations directly,
 * but receives names that have been ejected from L2.
 */
contract L1ETHRegistry is PermissionedRegistry {
    uint256 private constant ROLE_SET_EJECTION_CONTROLLER = 1 << 5;
    uint256 private constant ROLE_SET_EJECTION_CONTROLLER_ADMIN = ROLE_SET_EJECTION_CONTROLLER << 128;

    error NameNotExpired(uint256 tokenId, uint64 expires);
    error OnlyEjectionController();

    event NameEjected(uint256 indexed tokenId, address owner, uint64 expires);
    event NameMigratedToL2(uint256 indexed tokenId, address sendTo);
    event EjectionControllerChanged(address oldController, address newController);

    IL1EjectionController public ejectionController;

    constructor(IRegistryDatastore _datastore, address _ejectionController, IRegistryMetadata _registryMetadata) PermissionedRegistry(_datastore, _registryMetadata) {
        // Set the ejection controller
        require(_ejectionController != address(0), "Ejection controller cannot be empty");
        ejectionController = IL1EjectionController(_ejectionController);
    }

    modifier onlyEjectionController() {
        if (msg.sender != address(ejectionController)) {
            revert OnlyEjectionController();
        }
        _;
    }

    /**
     * @dev Set a new ejection controller
     * @param _newEjectionController The address of the new controller
     */
    function setEjectionController(address _newEjectionController) external onlyRoles(ROOT_RESOURCE, ROLE_SET_EJECTION_CONTROLLER) {
        require(_newEjectionController != address(0), "Ejection controller cannot be empty");
        
        address oldController = address(ejectionController);
        
        // Set the new controller
        ejectionController = IL1EjectionController(_newEjectionController);
        
        emit EjectionControllerChanged(oldController, _newEjectionController);
    }

    /**
     * @dev Receive an ejected name from Namechain.
     * @param tokenId The token ID of the name
     * @param owner The owner of the name
     * @param registry The registry to use for the name
     * @param expires Expiration timestamp
     * @return tokenId The token ID of the ejected name
     */
    function ejectFromNamechain(uint256 tokenId, address owner, IRegistry registry, uint64 expires)
        public
        onlyEjectionController
        returns (uint256)
    {
        // Check if the name is active (not expired)
        (, uint64 oldExpires, uint32 tokenIdVersion) = datastore.getSubregistry(tokenId);
        if (oldExpires >= block.timestamp) {
            revert NameNotExpired(tokenId, oldExpires);
        }

        // Get the actual owner without checking expiration
        address actualOwner = ERC1155Singleton.ownerOf(tokenId);
        if (actualOwner != address(0)) {
            // Burn the token from the actual owner
            _burn(actualOwner, tokenId, 1);
        }

        _mint(owner, tokenId, 1, "");

        datastore.setSubregistry(tokenId, address(registry), expires, tokenIdVersion);

        emit NameEjected(tokenId, owner, expires);
        return tokenId;
    }

    /**
     * @dev Update expiration date for a name. This can only be called by the ejection controller
     * when it receives a notification from L2 about a renewal.
     *
     * @param tokenId The token ID of the name to update
     * @param expires New expiration timestamp
     */
    function updateExpiration(uint256 tokenId, uint64 expires) 
        public 
        onlyEjectionController
    {
        (address subregistry, uint64 oldExpiration, uint32 tokenIdVersion) = datastore.getSubregistry(tokenId);
        
        if (oldExpiration < block.timestamp) {
            revert NameExpired(tokenId);
        }
        
        if (expires < oldExpiration) {
            revert CannotReduceExpiration(oldExpiration, expires);
        }
        
        datastore.setSubregistry(tokenId, subregistry, expires, tokenIdVersion);
        
        emit NameRenewed(tokenId, expires, msg.sender);
    }

    /**
     * @dev Migrate a name back to Namechain, preserving ownership on Namechain.
     * According to section 4.5.6 of the design doc, this process requires
     * the ejection controller to facilitate cross-chain communication.
     * @param tokenId The token ID of the name to migrate
     * @param l2Owner The address to send the name to on L2
     * @param l2Subregistry The subregistry to use on L2 (optional)
     * @param data Extra data
     */
    function migrateToNamechain(uint256 tokenId, address l2Owner, address l2Subregistry, bytes memory data) external onlyTokenOwner(tokenId) {
        address owner = ownerOf(tokenId);
        _burn(owner, tokenId, 1);
        datastore.setSubregistry(tokenId, address(0), 0, 0);

        // Notify the ejection controller to handle cross-chain messaging
        ejectionController.migrateToNamechain(tokenId, l2Owner, l2Subregistry, data);

        emit NameMigratedToL2(tokenId, l2Owner);
    }


    function supportsInterface(bytes4 interfaceId) public view override(PermissionedRegistry) returns (bool) {
        return interfaceId == type(IRegistry).interfaceId || super.supportsInterface(interfaceId);
    }
}