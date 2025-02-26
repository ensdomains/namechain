// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (access/AccessControl.sol)

pragma solidity ^0.8.20;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @dev An enhanced version of OpenZeppelin's AccessControl that allows for:
 * 
 * - Context-based roles.
 * - Root context override (0x0) - role assignments in the root context auto-apply to all contexts.
 * - Removing all assignments of a given role from a context.
 */
abstract contract EnhancedAccessControl is Context, ERC165 {
    error EnhancedAccessControlUnauthorizedAccountRole(bytes32 context, bytes32 role, address account);
    error EnhancedAccessControlUnauthorizedAccountRoleGroup(bytes32 context, bytes32 roleGroup, address account);
    error EnhancedAccessControlBadConfirmation();

    event EnhancedAccessControlRoleAdminChanged(bytes32 role, bytes32 previousAdminRole, bytes32 newAdminRole);
    event EnhancedAccessControlRoleGroupChanged(bytes32 roleGroup, bytes32[] previousRoles, bytes32[] newRoles);
    event EnhancedAccessControlRoleGranted(bytes32 context, bytes32 role, address account, address sender);
    event EnhancedAccessControlRoleRevoked(bytes32 context, bytes32 role, address account, address sender);

    /** @dev user role within a context. */
    struct RoleAssignment {
        uint256 version;   // Version tying this assignment to the current role version - see _roleVersion below
        bool hasRole;      // Indicates if the user has the role
    }

    /** 
     * @dev admin role that controls a given role. 
     * Role -> AdminRole
     */
    mapping(bytes32 role => bytes32 adminRole) private _adminRoles;

    /** 
     * @dev Role groupings.
     * RoleGroup -> Roles
     */
    mapping(bytes32 roleGroup => bytes32[] roles) private _roleGroups;

    /**
     * @dev user role within a context.
     * Context -> Role -> User -> RoleAssignment
     */
    mapping(bytes32 context => mapping(bytes32 role => mapping(address account => RoleAssignment roleAssignment))) private _roles;

    /**
     * @dev We use a version number to track the changes to the role assignments.
     * This means we can easily remove all assignments of a given role without needing a loop.
     */
    mapping(bytes32 context => mapping(bytes32 role => uint256 version)) private _roleVersion;

    /**
     * @dev The root context.
     */
    bytes32 public constant ROOT_CONTEXT = bytes32(0);

    /**
     * @dev The default admin role.
     */
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Modifier that checks that sender has a specific role within the given context. 
     * Reverts with an {AccessControlUnauthorizedAccount} error including the required role.
     */
    modifier onlyRole(bytes32 context, bytes32 role) {
        _checkRole(context, role, _msgSender());
        _;
    }


    /**
     * @dev Modifier that checks that sender has a specific role within the given context. 
     * Reverts with an {AccessControlUnauthorizedAccount} error including the required role.
     */
    modifier onlyRoleGroup(bytes32 context, bytes32 roleGroup) {
        _checkRoleGroup(context, roleGroup, _msgSender());
        _;
    }

    /**
     * @dev Modifier that checks that sender has a specific role within the root context. 
     * Reverts with an {AccessControlUnauthorizedAccount} error including the required role.
     */
    modifier onlyRootRole(bytes32 role) {
        _checkRole(ROOT_CONTEXT, role, _msgSender());
        _;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(EnhancedAccessControl).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns `true` if `account` has been granted `role` in the root context.
     */
    function hasRootRole(bytes32 role, address account) public view virtual returns (bool) {
        if (_roles[ROOT_CONTEXT][role][account].hasRole && _roles[ROOT_CONTEXT][role][account].version == _roleVersion[ROOT_CONTEXT][role]) {
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 context, bytes32 role, address account) public view virtual returns (bool) {
        if (_roles[context][role][account].hasRole && _roles[context][role][account].version == _roleVersion[context][role]) {
            return true;
        } else {
            return hasRootRole(role, account);
        }
    }

    /**
     * @dev Reverts with an {AccessControlUnauthorizedAccount} error if `account`
     * is missing `role`.
     */
    function _checkRole(bytes32 context, bytes32 role, address account) internal view virtual {
        if (!hasRole(context, role, account)) {
            revert EnhancedAccessControlUnauthorizedAccountRole(context, role, account);
        }
    }

    /**
     * @dev Reverts with an {AccessControlUnauthorizedAccount} error if `account`
     * is missing `role`.
     */
    function _checkRoleGroup(bytes32 context, bytes32 roleGroup, address account) internal view virtual {
        bool hasAnyRole = false;
        bytes32[] memory roles = _roleGroups[roleGroup];
        for (uint256 i = 0; i < roles.length; i++) {
            if (hasRole(context, roles[i], account)) {
                hasAnyRole = true;
            }
        }
        if (!hasAnyRole) {
            revert EnhancedAccessControlUnauthorizedAccountRoleGroup(context, roleGroup, account);
        }
    }

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) public view virtual returns (bytes32) {
        return _adminRoles[role];
    }

    /**
     * @dev Grants `role` to `account`.
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
    function grantRole(bytes32 context, bytes32 role, address account) public virtual onlyRole(context, getRoleAdmin(role)) returns (bool) {
        return _grantRole(context, role, account);
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
    function revokeRole(bytes32 context, bytes32 role, address account) public virtual onlyRole(context, getRoleAdmin(role)) {
        _revokeRole(context, role, account);
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
     */
    function renounceRole(bytes32 context, bytes32 role, address callerConfirmation) public virtual {
        if (callerConfirmation != _msgSender()) {
            revert EnhancedAccessControlBadConfirmation();
        }

        _revokeRole(context, role, callerConfirmation);
    }

    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {EnhancedAccessControlRoleAdminChanged} event.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        bytes32 previousAdminRole = getRoleAdmin(role);
        _adminRoles[role] = adminRole;
        emit EnhancedAccessControlRoleAdminChanged(role, previousAdminRole, adminRole);
    }

    /**
     * @dev Sets `roles` as ``roleGroup``'s roles.
     *
     * Emits a {EnhancedAccessControlRoleGroupChanged} event.
     */
    function _setRoleGroup(bytes32 roleGroup, bytes32[] memory roles) internal virtual {
        bytes32[] memory previousRoles = _roleGroups[roleGroup];
        _roleGroups[roleGroup] = roles;     
        emit EnhancedAccessControlRoleGroupChanged(roleGroup, previousRoles, roles);
    }


    /**
     * @dev Revoke all assignments of a given role in a given context.
     */
    function _revokeRoleAssignments(bytes32 context, bytes32 role) internal virtual {
        _roleVersion[context][role]++;
    }

    /**
     * @dev Attempts to grant `role` to `account` and returns a boolean indicating if `role` was granted.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleGranted} event.
     */
    function _grantRole(bytes32 context, bytes32 role, address account) internal virtual returns (bool) {
        if (!hasRole(context, role, account)) {
            _roles[context][role][account] = RoleAssignment(_roleVersion[context][role], true);
            emit EnhancedAccessControlRoleGranted(context, role, account, _msgSender());
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Attempts to revoke `role` to `account` and returns a boolean indicating if `role` was revoked.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleRevoked} event.
     */
    function _revokeRole(bytes32 context, bytes32 role, address account) internal virtual returns (bool) {
        if (hasRole(context, role, account)) {
            _roles[context][role][account] = RoleAssignment(_roleVersion[context][role], false);
            emit EnhancedAccessControlRoleRevoked(context, role, account, _msgSender());
            return true;
        } else {
            return false;
        }
    }
}
