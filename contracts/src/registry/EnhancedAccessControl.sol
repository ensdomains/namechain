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
    error EnhancedAccessControlUnauthorizedAccount(uint256 context, bytes32 role, address account);
    error EnhancedAccessControlBadConfirmation();

    event EnhancedAccessControlRoleAdminChanged(bytes32 role, bytes32 previousAdminRole, bytes32 newAdminRole);
    event EnhancedAccessControlRoleGranted(uint256 context, bytes32 role, address account, address sender);
    event EnhancedAccessControlRoleRevoked(uint256 context, bytes32 role, address account, address sender);

    /** @dev user role within a context. */
    struct RoleAssignment {
        bool hasRole;      // Indicates if the user has the role
        uint256 version;   // Version tying this assignment to the current role version - see _roleVersion below
    }

    /** 
     * @dev admin role that controls a given role. 
     * Role -> AdminRole
     */
    mapping(bytes32 role => bytes32 adminRole) private _adminRoles;

    /**
     * @dev user role within a context.
     * Context -> Role -> User -> RoleAssignment
     */
    mapping(uint256 context => mapping(bytes32 role => mapping(address account => RoleAssignment roleAssignment))) private _roles;

    /**
     * @dev We use a version number to track the changes to the role assignments.
     * This means we can easily remove all assignments of a given role without needing a loop.
     */
    mapping(uint256 context => mapping(bytes32 role => uint256 version)) private _roleVersion;

    /**
     * @dev The root context.
     */
    uint256 public constant ROOT_CONTEXT = 0;

    /**
     * @dev The default admin role.
     */
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Modifier that checks that sender has a specific role within the given context. 
     * Reverts with an {AccessControlUnauthorizedAccount} error including the required role.
     */
    modifier onlyRole(uint256 context, bytes32 role) {
        _checkRole(context, role);
        _;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(EnhancedAccessControl).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(uint256 context, bytes32 role, address account) public view virtual returns (bool) {
        uint256 roleVersion = _roleVersion[context][role];
        uint256 roleVersionInRoot = _roleVersion[ROOT_CONTEXT][role];

        return (_roles[context][role][account].hasRole && _roles[context][role][account].version == roleVersion) ||
               (_roles[ROOT_CONTEXT][role][account].hasRole && _roles[ROOT_CONTEXT][role][account].version == roleVersionInRoot);
    }

    /**
     * @dev Reverts with an {AccessControlUnauthorizedAccount} error if `_msgSender()`
     * is missing `role`. Overriding this function changes the behavior of the {onlyRole} modifier.
     */
    function _checkRole(uint256 context, bytes32 role) internal view virtual {
        _checkRole(context, role, _msgSender());
    }

    /**
     * @dev Reverts with an {AccessControlUnauthorizedAccount} error if `account`
     * is missing `role`.
     */
    function _checkRole(uint256 context, bytes32 role, address account) internal view virtual {
        if (!hasRole(context, role, account)) {
            revert EnhancedAccessControlUnauthorizedAccount(context, role, account);
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
    function grantRole(uint256 context, bytes32 role, address account) public virtual onlyRole(context, getRoleAdmin(role)) {
        _grantRole(context, role, account);
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
    function revokeRole(uint256 context, bytes32 role, address account) public virtual onlyRole(context, getRoleAdmin(role)) {
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
    function renounceRole(uint256 context, bytes32 role, address callerConfirmation) public virtual {
        if (callerConfirmation != _msgSender()) {
            revert EnhancedAccessControlBadConfirmation();
        }

        _revokeRole(context, role, callerConfirmation);
    }

    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {RoleAdminChanged} event.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        bytes32 previousAdminRole = getRoleAdmin(role);
        _adminRoles[role] = adminRole;
        emit EnhancedAccessControlRoleAdminChanged(role, previousAdminRole, adminRole);
    }

    /**
     * @dev Revoke all assignments of a given role in a given context.
     */
    function _revokeRoleAssignments(uint256 context, bytes32 role) internal virtual {
        _roleVersion[context][role]++;
    }

    /**
     * @dev Attempts to grant `role` to `account` and returns a boolean indicating if `role` was granted.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleGranted} event.
     */
    function _grantRole(uint256 context, bytes32 role, address account) internal virtual returns (bool) {
        if (!hasRole(context, role, account)) {
            _roles[context][role][account].hasRole = true;
            _roles[context][role][account].version = _roleVersion[context][role];
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
    function _revokeRole(uint256 context, bytes32 role, address account) internal virtual returns (bool) {
        if (hasRole(context, role, account)) {
            _roles[context][role][account].hasRole = false;
            emit EnhancedAccessControlRoleRevoked(context, role, account, _msgSender());
            return true;
        } else {
            return false;
        }
    }
}
