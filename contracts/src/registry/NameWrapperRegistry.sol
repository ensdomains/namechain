// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC1155Singleton} from "./ERC1155Singleton.sol";
import {IERC1155Singleton} from "./IERC1155Singleton.sol";
import {IRegistry} from "./IRegistry.sol";
import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {BaseRegistry} from "./BaseRegistry.sol";
import {PermissionedRegistry} from "./PermissionedRegistry.sol";
import {EnhancedAccessControl} from "./EnhancedAccessControl.sol";

contract NameWrapperRegistry is PermissionedRegistry, EnhancedAccessControl {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");
    bytes32 public constant EMANCIPATOR_ROLE = keccak256("EMANCIPATOR_ROLE");
    bytes32 public constant EMANCIPATED_OWNER_ROLE = keccak256("EMANCIPATED_OWNER_ROLE");
    bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
    bytes32 public constant RENEW_ROLE = keccak256("RENEW_ROLE");

    error NameAlreadyRegistered(string label);
    error NameExpired(uint256 tokenId);
    error CannotReduceExpiration(uint64 oldExpiration, uint64 newExpiration);
    event NameRenewed(uint256 indexed tokenId, uint64 newExpiration, address renewedBy);

    constructor(IRegistryDatastore _datastore) PermissionedRegistry(_datastore) {
        _grantRole(ROOT_CONTEXT, DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function uri(uint256 /*tokenId*/ ) public pure override returns (string memory) {
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

    function register(string calldata label, address owner, IRegistry registry, uint96 flags, uint64 expires)
        public
        onlyRole(ROOT_CONTEXT, REGISTRAR_ROLE)
        returns (uint256 tokenId)
    {
        tokenId = (uint256(keccak256(bytes(label))) & ~uint256(FLAGS_MASK)) | flags;
        flags = (flags & FLAGS_MASK) | (uint96(expires) << 32);

        (, uint96 oldFlags) = datastore.getSubregistry(tokenId);
        uint64 oldExpiry = _extractExpiry(oldFlags);
        if (oldExpiry >= block.timestamp) {
            revert NameAlreadyRegistered(label);
        }

        // if there is a previous owner, burn the token
        address previousOwner = super.ownerOf(tokenId);
        if (previousOwner != address(0)) {
            _burn(previousOwner, tokenId, 1);
        }

        _mint(owner, tokenId, 1, "");
        datastore.setSubregistry(tokenId, address(registry), flags);

        // registrar has some permissions by default
        _grantRole(tokenId, RENEW_ROLE, msg.sender);
        _grantRole(tokenId, EMANCIPATOR_ROLE, msg.sender);
        _grantRole(tokenId, TRANSFER_ROLE, owner); // allow the owner to transfer the name

        emit NewSubname(label);
        return tokenId;
    }

    function renew(uint256 tokenId, uint64 expires) public onlyRole(tokenId, RENEW_ROLE) {
        address sender = _msgSender();

        (address subregistry, uint96 flags) = datastore.getSubregistry(tokenId);
        uint64 oldExpiration = _extractExpiry(flags);
        if (oldExpiration < block.timestamp) {
            revert NameExpired(tokenId);
        }
        if (expires < oldExpiration) {
            revert CannotReduceExpiration(oldExpiration, expires);
        }
        datastore.setSubregistry(tokenId, subregistry, (flags & FLAGS_MASK) | (uint96(expires) << 32));

        emit NameRenewed(tokenId, expires, sender);
    }

    /** 
     * @dev Emancipate the owner of the token. 
     * 
     * See v1 fuse: PARENT_CANNOT_CONTROL
     */
    function emancipate(uint256 tokenId) public onlyRole(tokenId, EMANCIPATOR_ROLE) {
        _grantRole(tokenId, EMANCIPATED_OWNER_ROLE, ownerOf(tokenId));
        renounceRole(tokenId, EMANCIPATOR_ROLE, msg.sender); // remove the emancipator role since we can only do this once.
    }
    
    /**
     * @dev Allow the owner to renew the name.
     * 
     * See v1 fuse: CAN_EXTEND_EXPIRY
     */
    function allowOwnerToRenew(uint256 tokenId) public onlyRole(tokenId, EMANCIPATED_OWNER_ROLE) {
        _grantRole(tokenId, RENEW_ROLE, ownerOf(tokenId));
    }



    /**
     * @dev Prevent anyone from renewing the name.
     * 
     * See v1 fuse: CANNOT_SET_TTL
     */
    function lockRenewals(uint256 tokenId) public onlyRole(tokenId, EMANCIPATED_OWNER_ROLE) {
        _revokeRoleAssignments(tokenId, RENEW_ROLE);
    }

    /**
     * @dev Prevent anyone from transferring the name.
     * 
     * See v1 fuse: CANNOT_TRANSFER
     */
    function lockTransfers(uint256 tokenId) public onlyRole(tokenId, EMANCIPATED_OWNER_ROLE) {
        _revokeRoleAssignments(tokenId, TRANSFER_ROLE);
    }

    /**
     * @dev Renounce the emancipated owner role.
     * 
     * See v1 fuse: CANNOT_BURN_FUSES
     */
    function renounceEmancipatedOwnerRole(uint256 tokenId) public onlyRole(tokenId, EMANCIPATED_OWNER_ROLE) {
        renounceRole(tokenId, EMANCIPATED_OWNER_ROLE, msg.sender);
    }


    function nameData(uint256 tokenId) external view returns (uint64 expiry, uint32 flags) {
        (, uint96 _flags) = datastore.getSubregistry(tokenId);
        return (_extractExpiry(_flags), uint32(_flags));
    }

    function setFlags(uint256 tokenId, uint96 flags)
        external
        onlyTokenOwner(tokenId)
        returns (uint256 newTokenId)
    {
        uint96 newFlags = _setFlags(tokenId, flags);
        newTokenId = (tokenId & ~uint256(FLAGS_MASK)) | (newFlags & FLAGS_MASK);
        if (tokenId != newTokenId) {
            address owner = ownerOf(tokenId);
            _burn(owner, tokenId, 1);
            _mint(owner, newTokenId, 1, "");
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override(BaseRegistry, EnhancedAccessControl) returns (bool) {
        return interfaceId == type(IRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    function getSubregistry(string calldata label) external view virtual override returns (IRegistry) {
        (address subregistry, uint96 flags) = datastore.getSubregistry(uint256(keccak256(bytes(label))));
        uint64 expires = _extractExpiry(flags);
        if (expires <= block.timestamp) {
            return IRegistry(address(0));
        }
        return IRegistry(subregistry);
    }

    function getResolver(string calldata label) external view virtual override returns (address) {
        uint256 tokenId = uint256(keccak256(bytes(label)));
        (, uint96 flags) = datastore.getSubregistry(tokenId);
        uint64 expires = _extractExpiry(flags);
        if (expires <= block.timestamp) {
            return address(0);
        }

        (address resolver, ) = datastore.getResolver(tokenId);
        return resolver;
    }
    
    // override the _updateWithAcceptanceCheck to check if the transfer lock setting has been set
    function _updateWithAcceptanceCheck(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) internal virtual override {
        address operator = _msgSender();

        // if it's not a mint or burn, check that transfer is possible
        if (to != address(0) && from != address(0)) {
            for (uint256 i = 0; i < ids.length; i++) {  
                _checkRole(ids[i], TRANSFER_ROLE, operator);
            }
        }

        super._updateWithAcceptanceCheck(from, to, ids, values, data);
    }

    // Private methods

    function _extractExpiry(uint96 flags) private pure returns (uint64) {
        return uint64(flags >> 32);
    }
}

/**
 * @dev Observer pattern for events on existing tokens.
 */
interface ETHRegistryTokenObserver {
    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external;
    function onRelinquish(uint256 tokenId, address relinquishedBy) external;
}