// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {ERC1155Singleton} from "./ERC1155Singleton.sol";
import {IERC1155Singleton} from "./IERC1155Singleton.sol";
import {IRegistry} from "./IRegistry.sol";
import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {BaseRegistry} from "./BaseRegistry.sol";
import {PermissionedRegistry} from "./PermissionedRegistry.sol";

contract NameWrapperRegistry is PermissionedRegistry, AccessControl {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    error NameAlreadyRegistered(string label);
    error NameExpired(uint256 tokenId);
    error CannotReduceExpiration(uint64 oldExpiration, uint64 newExpiration);
    event NameRenewed(uint256 indexed tokenId, uint64 newExpiration, address renewedBy);
    error AccessDeniedRenewal(address account);
    error RenewalsLocked(uint256 tokenId);
    error AccessDeniedUpdateSettings(address account);
    error SettingsLocked(uint256 tokenId, uint32 settings, uint32 mask, uint32 expected);

    address public parentRegistry;
    uint256 public parentTokenId;

    // TODO: uint32 for now whilst we iterate on the settings
    mapping(uint256 tokenId => uint32 flags) public settings;
    // Fuse: PARENT_CANNOT_CONTROL - the parent registry will have to lock this subregistry to its parent node + also set this setting here
    uint32 public constant SETTING_REGISTRAR_OWNER_HAS_CONTROL = 0x1;
    // Fuse: CAN_EXTEND_EXPIRY - to be called by parent registry
    uint32 public constant SETTING_REGISTRAR_OWNER_CAN_RENEW = 0x2;
    // Fuse: CANNOT_BURN_FUSES
    uint32 public constant SETTING_OWNER_SETTINGS_LOCKED = 0x4;
    // Fuse: CANNOT_RENEW
    uint32 public constant SETTING_OWNER_RENEWALS_LOCKED = 0x8;
    // Fuse: CANNOT_TRANSFER   
    uint32 public constant SETTING_OWNER_TRANSFER_LOCKED = 0x16;

    uint32 public constant SETTINGS_OWNER_MASK = 0x28; // 11100
    uint32 public constant SETTINGS_REGISTRAR_MASK = 0x3; // 11

    modifier withSettings(uint256 tokenId, uint32 mask, uint32 expected) {
        if ((settings[tokenId] & mask) != expected) {
            revert SettingsLocked(tokenId, settings[tokenId], mask, expected);
        }
        _;
    }

    constructor(IRegistryDatastore _datastore, address _parentRegistry, uint256 _parentTokenId) PermissionedRegistry(_datastore) {
        parentRegistry = _parentRegistry;
        parentTokenId = _parentTokenId;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
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
        onlyRole(REGISTRAR_ROLE)
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

        emit NewSubname(label);
        return tokenId;
    }

    function renew(uint256 tokenId, uint64 expires) public withSettings(tokenId, SETTING_OWNER_RENEWALS_LOCKED, 0) {
        address sender = _msgSender();
        // either have to be the registrar
        if (!hasRole(REGISTRAR_ROLE, sender)) {
            // or have the can renew flag set and caller must be token owner
            if (ownerOf(tokenId) != sender || (settings[tokenId] & SETTING_REGISTRAR_OWNER_CAN_RENEW) == 0) {
                revert AccessDeniedRenewal(sender);
            }
        }

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

    function updateOwnerSettings(uint256 _tokenId, uint32 _settings) public onlyTokenOwner(_tokenId) 
        withSettings(_tokenId, SETTING_OWNER_SETTINGS_LOCKED, 0) 
        withSettings(_tokenId, SETTING_REGISTRAR_OWNER_HAS_CONTROL, 1)
    {
        settings[_tokenId] = (_settings & SETTINGS_OWNER_MASK) | (settings[_tokenId] & SETTINGS_REGISTRAR_MASK);
    }

    function updateRegistrarSettings(uint256 _tokenId, uint32 _settings) public 
        onlyRole(REGISTRAR_ROLE) withSettings(_tokenId, SETTING_OWNER_SETTINGS_LOCKED, 0) 
        withSettings(_tokenId, SETTING_REGISTRAR_OWNER_HAS_CONTROL, 0)
    {
        settings[_tokenId] = (_settings & SETTINGS_REGISTRAR_MASK) | (settings[_tokenId] & SETTINGS_OWNER_MASK);
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

    function supportsInterface(bytes4 interfaceId) public view override(BaseRegistry, AccessControl) returns (bool) {
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
        // if it's not a mint or burn, check if the transfer lock setting has been set
        if (to != address(0) && from != address(0)) {
            for (uint256 i = 0; i < ids.length; i++) {  
                if (settings[ids[i]] & SETTING_OWNER_TRANSFER_LOCKED != 0) {
                    revert SettingsLocked(ids[i], settings[ids[i]], SETTING_OWNER_TRANSFER_LOCKED, 0);
                }
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
