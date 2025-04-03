// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (access/AccessControl.sol)

pragma solidity ^0.8.20;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";



/**
 * @dev Access control system that allows for:
 * 
 * - Resource-based roles.
 * - Root resource override (0x0) - role assignments in the `ROOT_RESOURCE` auto-apply to all resources.
 * - Upto 128 roles - stored as a bitmap in uint256 (see below).
 * 
 * Role representation:
 * - A role bitmap is a uint256, where the lower 128 bits represent the roles, and the upper 128 bits represent the admin roles for those roles.
 * - The admin role for a given role is the role shifted left by 128 bits.
 */
abstract contract EnhancedAccessControl is Context, ERC165 {
    error EACUnauthorizedAccountRoles(bytes32 resource, uint256 roleBitmap, address account);
    error EACUnauthorizedAccountAdminRoles(bytes32 resource, uint256 roleBitmap, address account);
    error EACRootResourceNotAllowed();

    event EACRolesGranted(bytes32 resource, uint256 roleBitmap, address account);
    event EACRolesRevoked(bytes32 resource, uint256 roleBitmap, address account);
    event EACAllRolesRevoked(bytes32 resource, address account);

    uint256 constant public ALL_ROLES = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    uint256 constant public ADMIN_ROLES = 0xffffffffffffffffffffffffffffffff00000000000000000000000000000000;

    /**
     * @dev user roles within a resource stored as a bitmap.
     * Resource -> User -> RoleBitmap
     */
    mapping(bytes32 resource => mapping(address account => uint256 roleBitmap)) private _roles;

    /**
     * @dev The `ROOT_RESOURCE`.
     */
    bytes32 public constant ROOT_RESOURCE = bytes32(0);
    

    /**
     * @dev Modifier that checks that sender has the admin roles for all the given roles. 
     */
    modifier canGrantRoles(bytes32 resource, uint256 roleBitmap) {
        _checkCanGrantRoles(resource, roleBitmap, _msgSender());
        _;
    }

    /**
     * @dev Modifier that checks that sender has all the given roles within the given resource. 
     */
    modifier onlyRoles(bytes32 resource, uint256 roleBitmap) {
        _checkRoles(resource, roleBitmap, _msgSender());
        _;
    }

    /**
     * @dev Modifier that checks that sender has all the given roles within the `ROOT_RESOURCE`. 
     */
    modifier onlyRootRoles(uint256 roleBitmap) {
        _checkRoles(ROOT_RESOURCE, roleBitmap, _msgSender());
        _;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(EnhancedAccessControl).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns `true` if `account` has been granted all the given roles in the `ROOT_RESOURCE`.
     *
     * @param rolesBitmap The roles bitmap to check.
     * @param account The account to check.
     * @return `true` if `account` has been granted all the given roles in the `ROOT_RESOURCE`, `false` otherwise.
     */
    function hasRootRoles(uint256 rolesBitmap, address account) public view virtual returns (bool) {
        return _roles[ROOT_RESOURCE][account] & rolesBitmap == rolesBitmap;
    }

    /**
     * @dev Returns `true` if `account` has been granted all the given roles in `resource`.
     *
     * @param resource The resource to check.
     * @param rolesBitmap The roles bitmap to check.
     * @param account The account to check.
     * @return `true` if `account` has been granted all the given roles in either `resource` or the `ROOT_RESOURCE`, `false` otherwise.
     */
    function hasRoles(bytes32 resource, uint256 rolesBitmap, address account) public view virtual returns (bool) {
        return (_roles[ROOT_RESOURCE][account] | _roles[resource][account]) & rolesBitmap == rolesBitmap;
    }


    /**
     * @dev Grants roles to `account`.
     *
     * The caller must have all the necessary admin roles for the roles being granted.
     * Cannot be used with ROOT_RESOURCE directly, use grantRootRoles instead.
     *
     * @param resource The resource to grant roles within.
     * @param roleBitmap The roles bitmap to grant.
     * @param account The account to grant roles to.
     * @return `true` if the roles were granted, `false` otherwise.
     */
    function grantRoles(bytes32 resource, uint256 roleBitmap, address account) public virtual canGrantRoles(resource, roleBitmap) returns (bool) {
        if (resource == ROOT_RESOURCE) {
            revert EACRootResourceNotAllowed();
        }
        return _grantRoles(resource, roleBitmap, account, true);
    }

    /**
     * @dev Grants roles to `account` in the ROOT_RESOURCE.
     *
     * The caller must have all the necessary admin roles for the roles being granted.
     *
     * @param roleBitmap The roles bitmap to grant.
     * @param account The account to grant roles to.
     * @return `true` if the roles were granted, `false` otherwise.
     */
    function grantRootRoles(uint256 roleBitmap, address account) public virtual canGrantRoles(ROOT_RESOURCE, roleBitmap) returns (bool) {
        return _grantRoles(ROOT_RESOURCE, roleBitmap, account, true);
    }

    /**
     * @dev Revokes roles from `account`.
     *
     * The caller must have all the necessary admin roles for the roles being revoked.
     * Cannot be used with ROOT_RESOURCE directly, use revokeRootRoles instead.
     *
     * @param resource The resource to revoke roles within.
     * @param roleBitmap The roles bitmap to revoke.
     * @param account The account to revoke roles from.
     * @return `true` if the roles were revoked, `false` otherwise.
     */
    function revokeRoles(bytes32 resource, uint256 roleBitmap, address account) public virtual canGrantRoles(resource, roleBitmap) returns (bool) {
        if (resource == ROOT_RESOURCE) {
            revert EACRootResourceNotAllowed();
        }
        return _revokeRoles(resource, roleBitmap, account, true);
    }

    /**
     * @dev Revokes roles from `account` in the ROOT_RESOURCE.
     *
     * The caller must have all the necessary admin roles for the roles being revoked.
     *
     * @param roleBitmap The roles bitmap to revoke.
     * @param account The account to revoke roles from.
     * @return `true` if the roles were revoked, `false` otherwise.
     */
    function revokeRootRoles(uint256 roleBitmap, address account) public virtual canGrantRoles(ROOT_RESOURCE, roleBitmap) returns (bool) {
        return _revokeRoles(ROOT_RESOURCE, roleBitmap, account, true);
    }

    // Internal functions

    /**
     * @dev Reverts if `account` does not have all the given roles.
     */
    function _checkRoles(bytes32 resource, uint256 roleBitmap, address account) internal view virtual {
        if (!hasRoles(resource, roleBitmap, account)) {
            revert EACUnauthorizedAccountRoles(resource, roleBitmap, account);
        }
    }

    /**
     * @dev Reverts if `account` does not have the admin roles for all the given roles.
     */
    function _checkCanGrantRoles(bytes32 resource, uint256 roleBitmap, address account) internal view virtual {
        uint256 settableRoles = _getSettableRoles(resource, account);
        if ((roleBitmap & ~settableRoles) != 0) {
            revert EACUnauthorizedAccountAdminRoles(resource, roleBitmap, account);
        }
    }

    /**
     * @dev Copies all roles from `srcAccount` to `dstAccount` within the same resource.
     *
     * @param resource The resource to copy roles within.
     * @param srcAccount The account to copy roles from.
     * @param dstAccount The account to copy roles to.
     */
    function _copyRoles(bytes32 resource, address srcAccount, address dstAccount, bool enableCallbacks) internal virtual {
        uint256 srcRoles = _roles[resource][srcAccount];
        _grantRoles(resource, srcRoles, dstAccount, enableCallbacks);
    }

    /**
     * @dev Grants multiple roles to `account`.
     */
    function _grantRoles(bytes32 resource, uint256 roleBitmap, address account, bool enableCallbacks) internal virtual returns (bool) {
        uint256 currentRoles = _roles[resource][account];
        uint256 updatedRoles = currentRoles | roleBitmap;

        if (currentRoles != updatedRoles) {
            _roles[resource][account] = updatedRoles;
            if (enableCallbacks) {
                _onRolesGranted(resource, account, currentRoles, updatedRoles, roleBitmap);
            }
            emit EACRolesGranted(resource, roleBitmap, account);
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Attempts to revoke roles from `account` and returns a boolean indicating if roles were revoked.
     */
    function _revokeRoles(bytes32 resource, uint256 roleBitmap, address account, bool enableCallbacks) internal virtual returns (bool) {
        uint256 currentRoles = _roles[resource][account];
        uint256 updatedRoles = currentRoles & ~roleBitmap;
        
        if (currentRoles != updatedRoles) {
            _roles[resource][account] = updatedRoles;
            if (enableCallbacks) {
                _onRolesRevoked(resource, account, currentRoles, updatedRoles, roleBitmap);
            }
            emit EACRolesRevoked(resource, roleBitmap, account);
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Revoke all roles for account within resource.
     */
    function _revokeAllRoles(bytes32 resource, address account, bool enableCallbacks) internal virtual returns (bool) {
        return _revokeRoles(resource, ALL_ROLES, account, enableCallbacks);
    }

    /**
     * @dev Returns the settable roles for `account` within `resource`.
     * 
     * The settable roles are the roles that the account can grant/revoke.
     * 
     * @param resource The resource to get settable roles for.
     * @param account The account to get settable roles for.
     * @return The settable roles for `account` within `resource`.
     */
    function _getSettableRoles(bytes32 resource, address account) internal view virtual returns (uint256) {
        uint256 adminRoleBitmap = (_roles[resource][account] | _roles[ROOT_RESOURCE][account]) & ADMIN_ROLES;
        return adminRoleBitmap | (adminRoleBitmap >> 128);
    }

    /**
     * @dev Callback for when roles are granted.
     *
     * @param resource The resource that the roles were granted within.
     * @param account The account that the roles were granted to.
     * @param oldRoles The old roles for the account.
     * @param newRoles The new roles for the account.
     * @param roleBitmap The roles that were granted.
     */
    function _onRolesGranted(bytes32 resource, address account, uint256 oldRoles, uint256 newRoles, uint256 roleBitmap) internal virtual {}

    /**
     * @dev Callback for when roles are revoked.
     *
     * @param resource The resource that the roles were revoked within.
     * @param account The account that the roles were revoked from.
     * @param oldRoles The old roles for the account.
     * @param newRoles The new roles for the account.
     * @param roleBitmap The roles that were revoked.
     */
    function _onRolesRevoked(bytes32 resource, address account, uint256 oldRoles, uint256 newRoles, uint256 roleBitmap) internal virtual {}
}