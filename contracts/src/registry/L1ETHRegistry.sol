// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IL1EjectionController} from "../controller/IL1EjectionController.sol";
import {ERC1155Singleton} from "./ERC1155Singleton.sol";
import {IERC1155Singleton} from "./IERC1155Singleton.sol";
import {IRegistry} from "./IRegistry.sol";
import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {BaseRegistry} from "./BaseRegistry.sol";
import {PermissionedRegistry} from "./PermissionedRegistry.sol";
import {RegistryMetadata} from "./RegistryMetadata.sol";

/**
 * @title L1ETHRegistry
 * @dev L1 contract for .eth that holds ejected .eth names only.
 * Unlike the L2 ETHRegistry, this registry does not handle new registrations directly,
 * but receives names that have been ejected from L2.
 */
contract L1ETHRegistry is PermissionedRegistry, AccessControl {
    error NameNotExpired(uint256 tokenId, uint64 expires);
    error OnlyEjectionController();

    event NameEjected(uint256 indexed tokenId, address owner, uint64 expires);
    event NameMigratedToL2(uint256 indexed tokenId, address sendTo);
    event EjectionControllerChanged(address oldController, address newController);

    IL1EjectionController public ejectionController;

    constructor(IRegistryDatastore _datastore, address _ejectionController) PermissionedRegistry(_datastore, RegistryMetadata(address(0))) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

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
    function setEjectionController(address _newEjectionController) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newEjectionController != address(0), "Ejection controller cannot be empty");
        
        address oldController = address(ejectionController);
        
        // Set the new controller
        ejectionController = IL1EjectionController(_newEjectionController);
        
        emit EjectionControllerChanged(oldController, _newEjectionController);
    }

    /**
     * @dev Receive an ejected name from Namechain.
     * @param labelHash The keccak256 hash of the label
     * @param owner The owner of the name
     * @param registry The registry to use for the name
     * @param flags The base flags
     * @param expires Expiration timestamp
     * @return tokenId The token ID of the ejected name
     */
    function ejectFromNamechain(uint256 labelHash, address owner, IRegistry registry, uint32 flags, uint64 expires)
        public
        onlyEjectionController
        returns (uint256 tokenId)
    {
        tokenId = (labelHash & ~uint256(FLAGS_MASK)) | flags;
        uint96 fullFlags = (uint96(flags) & FLAGS_MASK) | (uint96(expires) << 32);

        // Check if there is a previous owner and verify the name is expired
        // to prevent malicious ejection controllers from overriding valid L1 names
        address previousOwner = super.ownerOf(tokenId);
        if (previousOwner != address(0)) {
            (, uint96 oldFlags) = datastore.getSubregistry(tokenId);
            uint64 oldExpires = _extractExpiry(oldFlags);
            if (oldExpires >= block.timestamp) {
                revert NameNotExpired(tokenId, oldExpires);
            }
            _burn(previousOwner, tokenId, 1);
        }

        _mint(owner, tokenId, 1, "");
        datastore.setSubregistry(tokenId, address(registry), fullFlags);
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
        (address subregistry, uint96 flags) = datastore.getSubregistry(tokenId);
        uint64 oldExpiration = _extractExpiry(flags);
        
        if (oldExpiration < block.timestamp) {
            revert NameExpired(tokenId);
        }
        
        if (expires < oldExpiration) {
            revert CannotReduceExpiration(oldExpiration, expires);
        }
        
        datastore.setSubregistry(tokenId, subregistry, (flags & FLAGS_MASK) | (uint96(expires) << 32));
        
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
        datastore.setSubregistry(tokenId, address(0), 0);

        // Notify the ejection controller to handle cross-chain messaging
        ejectionController.migrateToNamechain(tokenId, l2Owner, l2Subregistry, data);

        emit NameMigratedToL2(tokenId, l2Owner);
    }


    function supportsInterface(bytes4 interfaceId) public view override(PermissionedRegistry, AccessControl) returns (bool) {
        return interfaceId == type(IRegistry).interfaceId || super.supportsInterface(interfaceId);
    }
}
