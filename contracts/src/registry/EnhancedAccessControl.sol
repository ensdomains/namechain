// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (access/AccessControl.sol)

pragma solidity ^0.8.20;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @dev An enhanced version of OpenZeppelin's AccessControl that allows for:
 * 
 * - Resource-based roles.
 * - Root resource override (0x0) - role assignments in the root resource auto-apply to all resources.
 * - Max 256 roles stored as a bitmap in uint256.
 */
abstract contract EnhancedAccessControl is Context, ERC165 {
    error EnhancedAccessControlUnauthorizedAccountRole(bytes32 resource, uint8 roleId, address account);
    error EnhancedAccessControlUnauthorizedAccountAdminRole(bytes32 resource, uint8 roleId, address account);
    error EnhancedAccessControlBadConfirmation();

    event EnhancedAccessControlRoleAdminChanged(uint8 roleId, uint8 previousAdminRoleId, uint8 newAdminRoleId);
    event EnhancedAccessControlRoleGranted(bytes32 resource, uint8 roleId, address account, address sender);
    event EnhancedAccessControlRolesGranted(bytes32 resource, uint256 roleBitmap, address account, address sender);
    event EnhancedAccessControlRoleRevoked(bytes32 resource, uint8 roleId, address account, address sender);
    event EnhancedAccessControlAllRolesRevoked(bytes32 resource, address account, address sender);

    /** 
     * @dev admin role that controls a given role. 
     * RoleId -> AdminRoleId
     */
    mapping(uint8 roleId => uint8 adminRoleId) private _adminRoles;

    /**
     * @dev user roles within a resource stored as a bitmap.
     * Resource -> User -> RoleBitmap
     */
    mapping(bytes32 resource => mapping(address account => uint256 roleBitmap)) private _roles;

    /**
     * @dev The root resource.
     */
    bytes32 public constant ROOT_RESOURCE = bytes32(0);

    /**
     * @dev The default admin role.
     */
    uint8 public constant DEFAULT_ADMIN_ROLE = 1;

    /**
     * @dev Modifier that checks that sender has the admin role for the given role. 
     * If the sender does not have the admin role, it checks that the sender has the DEFAULT_ADMIN_ROLE.
     */
    modifier canGrantRole(bytes32 resource, uint8 roleId) {
        _checkCanGrantRole(resource, roleId, _msgSender());
        _;
    }

    /**
     * @dev Modifier that checks that sender has a specific role within the given resource. 
     * Reverts with an {AccessControlUnauthorizedAccount} error including the required role.
     */
    modifier onlyRole(bytes32 resource, uint8 roleId) {
        _checkRole(resource, roleId, _msgSender());
        _;
    }

    /**
     * @dev Modifier that checks that sender has a specific role within the root resource. 
     * Reverts with an {AccessControlUnauthorizedAccount} error including the required role.
     */
    modifier onlyRootRole(uint8 roleId) {
        _checkRole(ROOT_RESOURCE, roleId, _msgSender());
        _;
    }

    /**
     * @dev Constructor.
     *
     * @param initialAdmin The address to grant the DEFAULT_ADMIN_ROLE to.
     */
    constructor(address initialAdmin) {
        _grantRole(ROOT_RESOURCE, DEFAULT_ADMIN_ROLE, initialAdmin);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(EnhancedAccessControl).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns `true` if `account` has been granted `roleId` in the root resource.
     */
    function hasRootRole(uint8 roleId, address account) public view virtual returns (bool) {
        return (_roles[ROOT_RESOURCE][account] & (1 << roleId)) != 0;
    }

    /**
     * @dev Returns `true` if `account` has been granted `roleId`.
     */
    function hasRole(bytes32 resource, uint8 roleId, address account) public view virtual returns (bool) {
        return ((_roles[resource][account] & (1 << roleId)) != 0) || hasRootRole(roleId, account);
    }


    /**
     * @dev Returns the admin role that controls `roleId`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function getRoleAdmin(uint8 roleId) public view virtual returns (uint8) {
        return _adminRoles[roleId];
    }

    /**
     * @dev Grants role to `account`.
     *
     * If `account` had not been already granted `roleId`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``roleId``'s admin role.
     *
     * May emit a {RoleGranted} event.
     */
    function grantRole(bytes32 resource, uint8 roleId, address account) public virtual canGrantRole(resource, roleId) returns (bool) {
        return _grantRole(resource, roleId, account);
    }



    /**
     * @dev Revokes `roleId` from `account`.
     *
     * If `account` had been granted `roleId`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``roleId``'s admin role.
     *
     * May emit a {RoleRevoked} event.
     */
    function revokeRole(bytes32 resource, uint8 roleId, address account) public virtual canGrantRole(resource, roleId) {
        _revokeRole(resource, roleId, account);
    }

    /**
     * @dev Revokes `roleId` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been revoked `roleId`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `callerConfirmation`.
     *
     * May emit a {RoleRevoked} event.
     */
    function renounceRole(bytes32 resource, uint8 roleId, address callerConfirmation) public virtual {
        if (callerConfirmation != _msgSender()) {
            revert EnhancedAccessControlBadConfirmation();
        }

        _revokeRole(resource, roleId, callerConfirmation);
    }

    // Internal functions

    /**
     * @dev Reverts with an {AccessControlUnauthorizedAccount} error if `account`
     * is missing `roleId`.
     */
    function _checkRole(bytes32 resource, uint8 roleId, address account) internal view virtual {
        if (!hasRole(resource, roleId, account)) {
            revert EnhancedAccessControlUnauthorizedAccountRole(resource, roleId, account);
        }
    }

    /**
     * @dev Reverts with an {AccessControlUnauthorizedAccount} error if account does not have the admin role for the given role.
     */
    function _checkCanGrantRole(bytes32 resource, uint8 roleId, address account) internal view virtual {
        uint8 theAdminRole = getRoleAdmin(roleId);
        if (!hasRole(resource, theAdminRole, account)) {
            if (!hasRole(resource, DEFAULT_ADMIN_ROLE, account)) {
                revert EnhancedAccessControlUnauthorizedAccountAdminRole(resource, roleId, account);
            }
        }
    }

    /**
     * @dev Copies all roles from `srcAccount` to `dstAccount`.
     *
     * @param resource The resource this applies to.
     * @param srcAccount The account to copy roles from.
     * @param dstAccount The account to copy roles to.
     */
    function _copyRoles(bytes32 resource, address srcAccount, address dstAccount) internal virtual {
        uint256 srcRoles = _roles[resource][srcAccount];
        _roles[resource][dstAccount] = srcRoles;
    }



    /**
     * @dev Sets `adminRoleId` as ``roleId``'s admin role.
     *
     * Emits a {EnhancedAccessControlRoleAdminChanged} event.
     */
    function _setRoleAdmin(uint8 roleId, uint8 adminRoleId) internal virtual {
        uint8 previousAdminRoleId = getRoleAdmin(roleId);
        _adminRoles[roleId] = adminRoleId;
        emit EnhancedAccessControlRoleAdminChanged(roleId, previousAdminRoleId, adminRoleId);
    }



    /**
     * @dev Grants multiple roles to `account`.
     */
    function _grantRoles(bytes32 resource, uint256 roleBitmap, address account) internal {
        uint256 currentRoles = _roles[resource][account];
        uint256 updatedRoles = currentRoles | roleBitmap;
        if (currentRoles != updatedRoles) {
            _roles[resource][account] = updatedRoles;
            emit EnhancedAccessControlRolesGranted(resource, roleBitmap, account, _msgSender());
        }
    }


    /**
     * @dev Attempts to grant `roleId` to `account` and returns a boolean indicating if `roleId` was granted.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleGranted} event.
     */
    function _grantRole(bytes32 resource, uint8 roleId, address account) internal virtual returns (bool) {
        uint256 currentRoles = _roles[resource][account];
        uint256 updatedRoles = currentRoles | (1 << roleId);
        
        if (currentRoles != updatedRoles) {
            _roles[resource][account] = updatedRoles;
            emit EnhancedAccessControlRoleGranted(resource, roleId, account, _msgSender());
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Attempts to revoke `roleId` to `account` and returns a boolean indicating if `roleId` was revoked.
     *
     * Internal function without access restriction.
     *
     * May emit a {RoleRevoked} event.
     */
    function _revokeRole(bytes32 resource, uint8 roleId, address account) internal virtual returns (bool) {
        uint256 currentRoles = _roles[resource][account];
        uint256 updatedRoles = currentRoles & ~(1 << roleId);
        
        if (currentRoles != updatedRoles) {
            _roles[resource][account] = updatedRoles;
            emit EnhancedAccessControlRoleRevoked(resource, roleId, account, _msgSender());
            return true;
        } else {
            return false;
        }
    }


    /**
     * @dev Revoke all roles for account within resource.
     */
    function _revokeAllRoles(bytes32 resource, address account) internal virtual {
        _roles[resource][account] = 0;
        emit EnhancedAccessControlAllRolesRevoked(resource, account, _msgSender());
    }
}
