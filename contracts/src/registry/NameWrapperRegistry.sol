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
    bytes32 public constant RENEW_ROLE = keccak256("RENEW_ROLE");

    error NameAlreadyRegistered(string label);
    error NameExpired(uint256 tokenId);
    error CannotReduceExpiration(uint64 oldExpiration, uint64 newExpiration);
    event NameRenewed(uint256 indexed tokenId, uint64 newExpiration, address renewedBy);
    error NameTransferLocked(uint256 tokenId);

    /**
     * @dev Prevents a name from being transferred.
     *
     * We use a boolean for this instead of roles due to the added complexity of dealing with 
     * ERC1155 approved operators if we were to use roles instead.
     */
    mapping(bytes32 tokenIdContext => bool locked) private transferLock;

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
        tokenId = _canonicalTokenId(uint256(keccak256(bytes(label))), flags);
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
        bytes32 tokenIdContext = _tokenIdContext(tokenId);
        _grantRole(tokenIdContext, RENEW_ROLE, msg.sender);
        _grantRole(tokenIdContext, EMANCIPATOR_ROLE, msg.sender);

        emit NewSubname(label);
        return tokenId;
    }

    function renew(uint256 tokenId, uint64 expires) public onlyRole(_tokenIdContext(tokenId), RENEW_ROLE) {
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
    function emancipate(uint256 tokenId) public onlyRole(_tokenIdContext(tokenId), EMANCIPATOR_ROLE) {
        bytes32 tokenIdContext = _tokenIdContext(tokenId);
        _grantRole(tokenIdContext, EMANCIPATED_OWNER_ROLE, ownerOf(tokenId));
        renounceRole(tokenIdContext, EMANCIPATOR_ROLE, msg.sender); // remove the emancipator role since we can only do this once.
    }
    
    /**
     * @dev Allow the owner to renew the name.
     * 
     * See v1 fuse: CAN_EXTEND_EXPIRY
     */
    function allowOwnerToRenew(uint256 tokenId) public onlyRole(_tokenIdContext(tokenId), EMANCIPATOR_ROLE) {
        bytes32 tokenIdContext = _tokenIdContext(tokenId);
        _grantRole(tokenIdContext, RENEW_ROLE, ownerOf(tokenId));
    }


    /**
     * @dev Prevent the name from being renewed.
     * 
     * See v1 fuse: CANNOT_SET_TTL
     */
    function lockRenewals(uint256 tokenId) public onlyRole(_tokenIdContext(tokenId), EMANCIPATED_OWNER_ROLE) {
        bytes32 tokenIdContext = _tokenIdContext(tokenId);
        _revokeRoleAssignments(tokenIdContext, RENEW_ROLE);
    }

    /**
     * @dev Prevent the name from being transferred.
     * 
     * See v1 fuse: CANNOT_TRANSFER
     */
    function lockTransfers(uint256 tokenId) public onlyRole(_tokenIdContext(tokenId), EMANCIPATED_OWNER_ROLE) {
        bytes32 tokenIdContext = _tokenIdContext(tokenId);
        transferLock[tokenIdContext] = true;
    }

    /**
     * @dev Renounce the emancipated owner role.
     * 
     * See v1 fuse: CANNOT_BURN_FUSES
     */
    function renounceEmancipatedOwnerRole(uint256 tokenId) public onlyRole(_tokenIdContext(tokenId), EMANCIPATED_OWNER_ROLE) {
        bytes32 tokenIdContext = _tokenIdContext(tokenId);
        renounceRole(tokenIdContext, EMANCIPATED_OWNER_ROLE, msg.sender);
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

            // NOTE: the role assignments can stay as they are since the 
            // token's role assignment context value remains unchanged.
            // @see _tokenIdContext
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
              if (transferLock[_tokenIdContext(ids[i])]) {
                revert NameTransferLocked(ids[i]);
              }
            }
        }

        super._updateWithAcceptanceCheck(from, to, ids, values, data);
    }

    // Private methods

    function _extractExpiry(uint96 flags) private pure returns (uint64) {
        return uint64(flags >> 32);
    }

    function _tokenIdContext(uint256 tokenId) private pure returns (bytes32) {
        return bytes32(tokenId & ~uint256(FLAGS_MASK));
    }

    function _canonicalTokenId(uint256 tokenId, uint96 flags) private pure returns (uint256) {
        return (tokenId & ~uint256(FLAGS_MASK)) | (flags & FLAGS_MASK);
    }
}

/**
 * @dev Observer pattern for events on existing tokens.
 */
interface ETHRegistryTokenObserver {
    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external;
    function onRelinquish(uint256 tokenId, address relinquishedBy) external;
}