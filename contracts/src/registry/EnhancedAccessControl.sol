// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (access/AccessControl.sol)

pragma solidity ^0.8.20;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @dev Access control system that allows for:
 * 
 * - Resource-based roles.
 * - Root resource override (0x0) - role assignments in the root resource auto-apply to all resources.
 * - Max 256 roles - stored as a bitmap in uint256.
 */
abstract contract EnhancedAccessControl is Context, ERC165 {
    error EACUnauthorizedAccountRole(bytes32 resource, uint256 role, address account);
    error EACUnauthorizedAccountAdminRole(bytes32 resource, uint256 role, address account);
    error EACBadConfirmation();
    error EACLockedRole(bytes32 resource, uint256 role);

    event EACRoleAdminChanged(uint256 role, uint256 previousAdminRole, uint256 newAdminRole);
    event EACRoleGranted(bytes32 resource, uint256 role, address account, address sender);
    event EACRolesGranted(bytes32 resource, uint256 roleBitmap, address account, address sender);
    event EACRolesCopied(bytes32 srcResource, bytes32 dstResource, address account, address sender, uint256 roleBitmap);
    event EACRolesRevoked(bytes32 resource, uint256 role, address account, address sender);
    event EACAllRolesRevoked(bytes32 resource, address account, address sender);
    event EACRolesLocked(bytes32 resource, uint256 roleBitmap);

    /** 
     * @dev admin role that controls a given role. 
     * RoleId -> AdminRoleId
     */
    mapping(uint256 role => uint256 adminRole) private _adminRoles;

    /**
     * @dev user roles within a resource stored as a bitmap.
     * Resource -> User -> RoleBitmap
     */
    mapping(bytes32 resource => mapping(address account => uint256 roleBitmap)) private _roles;

    /**
     * @dev locked roles within a resource stored as a bitmap.
     * Resource -> LockedRoleBitmap
     */
    mapping(bytes32 resource => uint256 lockedRoleBitmap) private _lockedRoles;

    /**
     * @dev The root resource.
     */
    bytes32 public constant ROOT_RESOURCE = bytes32(0);

    /**
     * @dev The default admin role.
     */
    uint256 public constant DEFAULT_ADMIN_ROLE = 1;

    /**
     * @dev Modifier that checks that sender has the admin role for the given role. 
     * If the sender does not have the admin role, it checks that the sender has the DEFAULT_ADMIN_ROLE.
     */
    modifier canGrantRole(bytes32 resource, uint256 role) {
        _checkCanGrantRole(resource, role, _msgSender());
        _;
    }

    /**
     * @dev Modifier that checks that sender has a specific role within the given resource. 
     * Reverts with an {AccessControlUnauthorizedAccount} error including the required role.
     */
    modifier onlyRole(bytes32 resource, uint256 role) {
        _checkRole(resource, role, _msgSender());
        _;
    }

    /**
     * @dev Modifier that checks that sender has a specific role within the root resource. 
     * Reverts with an {AccessControlUnauthorizedAccount} error including the required role.
     */
    modifier onlyRootRole(uint256 role) {
        _checkRole(ROOT_RESOURCE, role, _msgSender());
        _;
    }

    /**
     * @dev Constructor.
     *
     * @param initialAdmin The address to grant the DEFAULT_ADMIN_ROLE to.
     */
    constructor(address initialAdmin) {
        _grantRoles(ROOT_RESOURCE, DEFAULT_ADMIN_ROLE, initialAdmin);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(EnhancedAccessControl).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns `true` if `account` has been granted all roles in the root resource.
     */
    function hasRootRoles(uint256 rolesBitmap, address account) public view virtual returns (bool) {
        return (_roles[ROOT_RESOURCE][account] & rolesBitmap) != 0;
    }

    /**
     * @dev Returns `true` if `account` has been granted all roles in `resource`.
     */
    function hasRoles(bytes32 resource, uint256 rolesBitmap, address account) public view virtual returns (bool) {
        return ((_roles[resource][account] & rolesBitmap) != 0) || hasRootRoles(rolesBitmap, account);
    }


    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function getRoleAdmin(uint256 role) public view virtual returns (uint256) {
        return _adminRoles[role];
    }

    /**
     * @dev Returns the locked roles bitmap for a resource.
     */
    function getLockedRoles(bytes32 resource) public view virtual returns (uint256) {
        return _lockedRoles[resource];
    }

    /**
     * @dev Grants role to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     *
     * May emit a {RoleGranted} event.
     */
    function grantRole(bytes32 resource, uint256 role, address account) public virtual canGrantRole(resource, role) returns (bool) {
        return _grantRoles(resource, role, account);
    }


    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     *
     * May emit a {RoleRevoked} event.
     */
    function revokeRole(bytes32 resource, uint256 role, address account) public virtual canGrantRole(resource, role) returns (bool) {
        return _revokeRoles(resource, role, account);
    }


    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been revoked `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `callerConfirmation`.
     *
     * May emit a {RoleRevoked} event.
        *
     * Returns `true` if the role was revoked, `false` otherwise.
     */
    function renounceRole(bytes32 resource, uint256 role, address callerConfirmation) public virtual returns (bool) {
        if (callerConfirmation != _msgSender()) {
            revert EACBadConfirmation();
        }

        return _revokeRoles(resource, role, callerConfirmation);
    }

    // Internal functions

    /**
     * @dev Reverts with an {AccessControlUnauthorizedAccount} error if `account`
     * is missing `role`.
     */
    function _checkRole(bytes32 resource, uint256 role, address account) internal view virtual {
        if (!hasRoles(resource, role, account)) {
            revert EACUnauthorizedAccountRole(resource, role, account);
        }
    }

    /**
     * @dev Reverts with an {AccessControlUnauthorizedAccount} error if account does not have the admin role for the given role.
     */
    function _checkCanGrantRole(bytes32 resource, uint256 role, address account) internal view virtual {
        uint256 theAdminRole = getRoleAdmin(role);
        if (!hasRoles(resource, theAdminRole, account)) {
            if (!hasRoles(resource, DEFAULT_ADMIN_ROLE, account)) {
                revert EACUnauthorizedAccountAdminRole(resource, role, account);
            }
        }
    }

    /**
     * @dev Locks roles within a resource to prevent their removal.
     * Adds to any existing locked roles.
     *
     * @param resource The resource to lock roles in.
     * @param roleBitmap The bitmap of roles to lock.
     */
    function _lockRoles(bytes32 resource, uint256 roleBitmap) internal virtual {
        _lockedRoles[resource] |= roleBitmap;
        emit EACRolesLocked(resource, roleBitmap);
    }

    /**
     * @dev Copies all roles from `srcAccount` in `srcResource` to `dstAccount` in `dstResource`.
     *
     * @param srcResource The resource to copy roles from.
     * @param srcAccount The account to copy roles from.
     * @param dstResource The resource to copy roles to.
     * @param dstAccount The account to copy roles to.
     */
    function _copyRoles(bytes32 srcResource, address srcAccount, bytes32 dstResource, address dstAccount) internal virtual {
        uint256 srcRoles = _roles[srcResource][srcAccount];
        _roles[dstResource][dstAccount] |= srcRoles;
        emit EACRolesCopied(srcResource, dstResource, srcAccount, dstAccount, srcRoles);
    }



    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {EACRoleAdminChanged} event.
     */
    function _setRoleAdmin(uint256 role, uint256 adminRole) internal virtual {
        uint256 previousAdminRoleId = getRoleAdmin(role);
        _adminRoles[role] = adminRole;
        emit EACRoleAdminChanged(role, previousAdminRoleId, adminRole);
    }



    /**
     * @dev Grants multiple roles to `account`.
     */
    function _grantRoles(bytes32 resource, uint256 roleBitmap, address account) internal virtual returns (bool){
        uint256 currentRoles = _roles[resource][account];
        uint256 updatedRoles = currentRoles | roleBitmap;
        if (currentRoles != updatedRoles) {
            _roles[resource][account] = updatedRoles;
            emit EACRolesGranted(resource, roleBitmap, account, _msgSender());
            return true;
        } else {
            return false;
        }
    }


    /**
     * @dev Attempts to revoke roles from `account` and returns a boolean indicating if roles were revoked.
     */
    function _revokeRoles(bytes32 resource, uint256 roleBitmap, address account) internal virtual returns (bool) {
        // Check if any of the roles being revoked are locked
        uint256 lockedRoleBitmap = _lockedRoles[resource];
        if ((roleBitmap & lockedRoleBitmap) != 0) {
            revert EACLockedRole(resource, roleBitmap & lockedRoleBitmap);
        }
        
        uint256 currentRoles = _roles[resource][account];
        uint256 updatedRoles = currentRoles & ~roleBitmap;
        
        if (currentRoles != updatedRoles) {
            _roles[resource][account] = updatedRoles;
            emit EACRolesRevoked(resource, roleBitmap, account, _msgSender());
            return true;
        } else {
            return false;
        }
    }


    /**
     * @dev Revoke all roles for account within resource.
     */
    function _revokeAllRoles(bytes32 resource, address account) internal virtual returns (bool) {
        return _revokeRoles(resource, _roles[resource][account], account);
    }
}
