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

/**
 * @title L1ETHRegistry
 * @dev L1 contract for .eth that holds ejected .eth names only.
 * Unlike the L2 ETHRegistry, this registry does not handle new registrations directly,
 * but receives names that have been ejected from L2.
 */
contract L1ETHRegistry is PermissionedRegistry, AccessControl {
    bytes32 public constant EJECTION_CONTROLLER_ROLE = keccak256("EJECTION_CONTROLLER_ROLE");

    error NameExpired(uint256 tokenId);
    error NameNotExpired(uint256 tokenId, uint64 expires);
    error CannotReduceExpiration(uint64 oldExpiration, uint64 newExpiration);

    event NameEjected(uint256 indexed tokenId, address owner, uint64 expires);
    event NameRenewed(uint256 indexed tokenId, uint64 newExpiration, address renewedBy);
    event NameMigratedToL2(uint256 indexed tokenId, address sendTo);
    event TokenObserverSet(uint256 indexed tokenId, address observer);

    // Map to track token observers for notification of renewal events
    mapping(uint256 => address) public tokenObservers;

    address public ejectionController;

    constructor(
        IRegistryDatastore _datastore,
        address _ejectionController
    ) PermissionedRegistry(_datastore) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        // Grant roles to the controllers
        require(_ejectionController != address(0), "Ejection controller cannot be empty");

        _ejectionController = ejectionController;
        _grantRole(EJECTION_CONTROLLER_ROLE, _ejectionController);
    }

    function uri(uint256 /*tokenId*/ ) public pure override returns (string memory) {
        // TODO: implement metadata uri
        return "";
    }

    function ownerOf(uint256 tokenId)
        public
        view
        virtual
        override(ERC1155Singleton, IERC1155Singleton)
        returns (address)
    {
        (, uint96 oldFlags) = datastore.getSubregistry(tokenId);
        uint64 expires = _extractExpiry(oldFlags);
        if (expires < block.timestamp) {
            return address(0);
        }
        return super.ownerOf(tokenId);
    }

    /**
     * @dev Receive an ejected name from L2.
     * @param labelHash The keccak256 hash of the label
     * @param owner The owner of the name
     * @param registry The registry to use for the name
     * @param flags The base flags
     * @param expires Expiration timestamp
     * @return tokenId The token ID of the ejected name
     */
    function ejectFromL2(uint256 labelHash, address owner, IRegistry registry, uint32 flags, uint64 expires)
        public
        onlyRole(EJECTION_CONTROLLER_ROLE)
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
     * @dev Renew an ejected name.
     * After renewal, the ejection controller should be notified to sync the update to L2.
     * 
     * @param tokenId The token ID of the name to renew
     * @param expires New expiration timestamp
     */
    function renew(uint256 tokenId, uint64 expires) public {
        (address subregistry, uint96 flags) = datastore.getSubregistry(tokenId);
        uint64 oldExpiration = _extractExpiry(flags);
        if (oldExpiration < block.timestamp) {
            revert NameExpired(tokenId);
        }
        if (expires < oldExpiration) {
            revert CannotReduceExpiration(oldExpiration, expires);
        }
        datastore.setSubregistry(tokenId, subregistry, (flags & FLAGS_MASK) | (uint96(expires) << 32));

        address observer = tokenObservers[tokenId];
        if (observer != address(0)) {
            L1ETHRegistryTokenObserver(observer).onRenew(tokenId, expires, msg.sender);
        }

        // Notify the ejection controller to sync the renewal to L2
        IL1EjectionController(ejectionController).syncRenewalToL2(tokenId, expires);

        emit NameRenewed(tokenId, expires, msg.sender);
    }

    /**
     * @dev Set the token observer for a name
     * @param tokenId The token ID of the name
     * @param _observer The observer address
     */
    function setTokenObserver(uint256 tokenId, address _observer) external onlyTokenOwner(tokenId) {
        tokenObservers[tokenId] = _observer;
        emit TokenObserverSet(tokenId, _observer);
    }

    /**
     * @dev Migrate a name back to L2, preserving ownership on L2.
     * According to section 4.5.6 of the design doc, this process requires
     * the ejection controller to facilitate cross-chain communication.
     * @param tokenId The token ID of the name to migrate
     * @param l2Owner The address to send the name to on L2
     * @param l2Subregistry The subregistry to use on L2 (optional)
     */
    function migrateToL2(
        uint256 tokenId,
        address l2Owner,
        address l2Subregistry
    )
        external
        onlyTokenOwner(tokenId)
    {
        address owner = ownerOf(tokenId);
        _burn(owner, tokenId, 1);
        datastore.setSubregistry(tokenId, address(0), 0);
        
        // Notify the ejection controller to handle cross-chain messaging
        IL1EjectionController(ejectionController).initiateL1ToL2Migration(
            tokenId,
            l2Owner,
            l2Subregistry
        );
        
        emit NameMigratedToL2(tokenId, l2Owner);
    }

    /**
     * @dev Get name data (expiry and flags)
     * @param tokenId The token ID of the name
     * @return expiry Expiration timestamp
     * @return flags Flags for the name
     */
    function nameData(uint256 tokenId) external view returns (uint64 expiry, uint32 flags) {
        (, uint96 _flags) = datastore.getSubregistry(tokenId);
        return (_extractExpiry(_flags), uint32(_flags));
    }

    /**
     * @dev Set flags for a name
     * @param tokenId The token ID of the name
     * @param flags The new flags
     * @return newTokenId The new token ID (may change if flags affect the ID)
     */
    function setFlags(uint256 tokenId, uint96 flags) external onlyTokenOwner(tokenId) returns (uint256 newTokenId) {
        uint96 newFlags = _setFlags(tokenId, flags);
        newTokenId = (tokenId & ~uint256(FLAGS_MASK)) | (newFlags & FLAGS_MASK);
        if (tokenId != newTokenId) {
            address owner = ownerOf(tokenId);
            _burn(owner, tokenId, 1);
            _mint(owner, newTokenId, 1, "");
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override(BaseRegistry, AccessControl) returns (bool) {
        return interfaceId == type(IRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Get the subregistry for a label
     * @param label The label to query
     * @return The registry for the label, or address(0) if not found or expired
     */
    function getSubregistry(string calldata label) external view virtual override returns (IRegistry) {
        (address subregistry, uint96 flags) = datastore.getSubregistry(uint256(keccak256(bytes(label))));
        uint64 expires = _extractExpiry(flags);
        if (expires <= block.timestamp) {
            return IRegistry(address(0));
        }
        return IRegistry(subregistry);
    }

    /**
     * @dev Get the resolver for a label
     * @param label The label to query
     * @return The resolver for the label or address(0) if not found or expired
     */
    function getResolver(string calldata label) external view virtual override returns (address) {
        uint256 tokenId = uint256(keccak256(bytes(label)));
        (, uint96 flags) = datastore.getSubregistry(tokenId);
        uint64 expires = _extractExpiry(flags);

        if (expires <= block.timestamp) {
            return address(0);
        }

        (address resolver,) = datastore.getResolver(tokenId);
        return resolver;
    }

    // Private methods

    function _extractExpiry(uint96 flags) private pure returns (uint64) {
        return uint64(flags >> 32);
    }
}

/**
 * @dev Observer pattern for events on existing tokens.
 */
interface L1ETHRegistryTokenObserver {
    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external;
}
