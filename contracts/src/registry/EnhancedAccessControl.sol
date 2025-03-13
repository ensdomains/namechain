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
 * A role is represented by a uint256:
 * - The bit that is set in the least significant 128 bits represent the role.
 * - The bit that is set in the most significant 128 bits represent the admin role.
 *
 * For the methods which take a `roleBitmap`, ensure that:
 * - The least significant bit represents the roles.
 * - The most significant bit represents the corresponding admin roles.
 *
 * NOTE:
 * - Extending contracts must initialize their own default roles as this contract does not do so.
 * - If two or more roles share the same admin role then these roles must ALWAYS be granted/revoked together.
 */
abstract contract EnhancedAccessControl is Context, ERC165 {
    error EACUnauthorizedAccountRoles(bytes32 resource, uint256 roleBitmap, address account);
    error EACUnauthorizedAccountAdminRoles(bytes32 resource, uint256 roleBitmap, address account);

    event EACRolesGranted(bytes32 resource, uint256 roleBitmap, address account, address sender);
    event EACRolesCopied(bytes32 srcResource, bytes32 dstResource, address account, address sender, uint256 roleBitmap);
    event EACRolesRevoked(bytes32 resource, uint256 roleBitmap, address account, address sender);
    event EACAllRolesRevoked(bytes32 resource, address account, address sender);

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
        return ((_roles[resource][account] | _roles[ROOT_RESOURCE][account]) & rolesBitmap) == rolesBitmap;
    }


    /**
     * @dev Grants roles to `account`.
     *
     * The caller must have all the necessary admin roles for the roles being granted.
     *
     * @param resource The resource to grant roles within.
     * @param roleBitmap The roles bitmap to grant.
     * @param account The account to grant roles to.
     * @return `true` if the roles were granted, `false` otherwise.
     */
    function grantRoles(bytes32 resource, uint256 roleBitmap, address account) public virtual canGrantRoles(resource, roleBitmap) returns (bool) {
        return _grantRoles(resource, roleBitmap, account);
    }


    /**
     * @dev Revokes roles from `account`.
     *
     * The caller must have all the necessary admin roles for the roles being revoked.
     *
     * @param resource The resource to revoke roles within.
     * @param roleBitmap The roles bitmap to revoke.
     * @param account The account to revoke roles from.
     * @return `true` if the roles were revoked, `false` otherwise.
     */
    function revokeRoles(bytes32 resource, uint256 roleBitmap, address account) public virtual canGrantRoles(resource, roleBitmap) returns (bool) {
        return _revokeRoles(resource, roleBitmap, account);
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
        uint256 adminRoles = roleBitmap & 0xffffffffffffffffffffffffffffffff00000000000000000000000000000000;
        if (adminRoles == 0 || !hasRoles(resource, adminRoles, account)) {
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
    function _copyRoles(bytes32 resource, address srcAccount, address dstAccount) internal virtual {
        uint256 srcRoles = _roles[resource][srcAccount];
        _roles[resource][dstAccount] |= srcRoles;
        emit EACRolesCopied(resource, resource, srcAccount, dstAccount, srcRoles);
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
