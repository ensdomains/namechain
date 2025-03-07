// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC1155Singleton} from "./ERC1155Singleton.sol";
import {IERC1155Singleton} from "./IERC1155Singleton.sol";
import {IRegistry} from "./IRegistry.sol";
import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {BaseRegistry} from "./BaseRegistry.sol";
import {PermissionedRegistry} from "./PermissionedRegistry.sol";

contract NameWrapperRegistry is PermissionedRegistry{
    error NameAlreadyRegistered(string label);
    error NameExpired(uint256 tokenId);
    error CannotReduceExpiration(uint64 oldExpiration, uint64 newExpiration);
    event NameRenewed(uint256 indexed tokenId, uint64 newExpiration, address renewedBy);
    error NameTransferLocked(uint256 tokenId);
    error RegistrarRoleOnlyInRootContext();

    event RegistrarRoleTransferred(address indexed previousRegistrar, address indexed newRegistrar);

    /* NOTE: no default admin is set, meaning there is no superuser with forever permissions */
    constructor(IRegistryDatastore _datastore, address _registrar) PermissionedRegistry(_datastore, address(0)) {
        _setRoleAdmin(ROLE_RENEW, ROLE_RENEWER_ADMIN);
        _setRoleAdmin(ROLE_RENEWER_ADMIN, ROLE_PARENT);
        _grantRoles(ROOT_RESOURCE, ROLE_PARENT | ROLE_RENEWER_ADMIN, _msgSender());
        _grantRoles(ROOT_RESOURCE, ROLE_BITMAP_REGISTRAR_DEFAULT, _registrar);
    }


    // ------------------------------------------------------------------------------------------------
    // BEGIN: Override role management functions to ensure registrar roles are managed correctly
    // ------------------------------------------------------------------------------------------------


    /**
     * @dev Grants a role to an account.
     * If the role is the registrar role, it will also grant the registrar default roles to the account.
     */
    function grantRole(bytes32 resource, uint256 role, address account) public override returns (bool) {
        if (super.grantRole(resource, role, account)) {
            if (resource == ROOT_RESOURCE && role == ROLE_REGISTRAR) {
                _grantRoles(ROOT_RESOURCE, ROLE_BITMAP_REGISTRAR_DEFAULT, account);
            }
            return true;
        }
        return false;
    }
    

    /**
     * @dev Revokes a role from an account.
     * If the role is the registrar role, it will also revoke the registrar default roles from the account.
     */
    function revokeRole(bytes32 resource, uint256 role, address account) public override returns (bool) {
        if (super.revokeRole(resource, role, account)) {
            if (resource == ROOT_RESOURCE && role == ROLE_REGISTRAR) {
                _revokeRoles(ROOT_RESOURCE, ROLE_BITMAP_REGISTRAR_DEFAULT, account);
            }
            return true;
        }
        return false;
    }


    /**
     * @dev Renounces a role.
     * If the role is the registrar role, it will also revoke the registrar default roles from the caller.
     */
    function renounceRole(bytes32 resource, uint256 role, address callerConfirmation) public override returns (bool) {
        if (super.renounceRole(resource, role, msg.sender)) {
            _revokeRoles(ROOT_RESOURCE, ROLE_BITMAP_REGISTRAR_DEFAULT, _msgSender());
            return true;
        }
        return false;
    }


    // ------------------------------------------------------------------------------------------------
    // END: Override role management functions to ensure registrar roles are managed correctly
    // ------------------------------------------------------------------------------------------------
    

    /**
     * @dev Disables the ability to grant/revoke the renewer role to/from anyone.
     *
     * NOTE: this essentially freezes the existing renewer role assignments.
     *
     * Can only be called by the parent role.
     */
    function freezeRenewerRole() public onlyRootRole(ROLE_PARENT) {
        _setRoleAdmin(ROLE_RENEW, 0);
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
        (bool isExpired, , ,) = _getStatus(tokenId);
        if (isExpired) {
            return address(0);
        }
        return super.ownerOf(tokenId);
    }

    function register(string calldata label, address owner, IRegistry registry, uint96 flags, uint64 expires)
        public
        onlyRootRole(ROLE_REGISTRAR)
        returns (uint256 tokenId)
    {
        tokenId = _canonicalTokenId(_labelToTokenId(label), flags);
        flags = (flags & FLAGS_MASK) | (uint96(expires) << 32);

        (bool isExpired, , ,) = _getStatus(tokenId);
        if (isExpired) {
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

    function renew(uint256 tokenId, uint64 expires) public onlyRole(tokenIdResource(tokenId), ROLE_RENEW) {
        address sender = _msgSender();

        (bool isExpired, uint64 oldExpiration, address subregistry, uint96 flags) = _getStatus(tokenId);
        if (isExpired) {
            revert NameExpired(tokenId);
        }
        if (expires < oldExpiration) {
            revert CannotReduceExpiration(oldExpiration, expires);
        }
        datastore.setSubregistry(tokenId, subregistry, (flags & FLAGS_MASK) | (uint96(expires) << 32));

        emit NameRenewed(tokenId, expires, sender);
    }


    function nameData(uint256 tokenId) external view returns (uint64 expiry, uint32 flags) {
        (, uint64 _expiry, , uint32 _flags) = _getStatus(tokenId);
        return (_expiry, _flags);
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

    function getSubregistry(string calldata label) external view virtual override returns (IRegistry subregistry) {
        (bool isExpired, , address subregistryAddress, ) = _getStatus(_labelToTokenId(label));
        if (isExpired) {
            return IRegistry(address(0));
        }
        return IRegistry(subregistryAddress);
    }

    function getResolver(string calldata label) external view virtual override returns (address) {
        uint256 tokenId = _labelToTokenId(label);
        (bool isExpired, , , ) = _getStatus(tokenId);
        if (isExpired) {
            return address(0);
        }
        (address resolver, ) = datastore.getResolver(tokenId);
        return resolver;
    }
    
    // Private methods

    function _getStatus(uint256 tokenId) private view returns (bool isExpired, uint64 expires, address subregistryAddress, uint32 flags) {
        uint96 _flags;
        (subregistryAddress, _flags) = datastore.getSubregistry(tokenId);
        expires = uint64(flags >> 32);
        flags = uint32(_flags);
        isExpired = expires <= block.timestamp;
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