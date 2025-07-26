// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @dev Interface for Enhanced Access Control system that allows for:
 * - Resource-based roles
 * - Obtaining assignee count for each role in each resource
 * - Root resource override
 * - Up to 32 roles and 32 corresponding admin roles
 * - Up to 15 assignees per role
 */
interface IEnhancedAccessControl is IERC165 {
    // Errors
    error EACUnauthorizedAccountRoles(bytes32 resource, uint256 roleBitmap, address account);
    error EACUnauthorizedAccountAdminRoles(bytes32 resource, uint256 roleBitmap, address account);
    error EACRootResourceNotAllowed();
    error EACMaxAssignees(bytes32 resource, uint256 role);
    error EACMinAssignees(bytes32 resource, uint256 role);
    error EACInvalidRoleBitmap(uint256 roleBitmap);

    // Events
    event EACRolesGranted(bytes32 resource, uint256 roleBitmap, address account);
    event EACRolesRevoked(bytes32 resource, uint256 roleBitmap, address account);
    event EACAllRolesRevoked(bytes32 resource, address account);

    /**
     * @dev Returns the `ROOT_RESOURCE` constant.
     */
    function ROOT_RESOURCE() external view returns (bytes32);

    /**
     * @dev Returns the roles bitmap for an account in a resource.
     */
    function roles(bytes32 resource, address account) external view returns (uint256);

    /**
     * @dev Returns the role count bitmap for a resource.
     */
    function roleCount(bytes32 resource) external view returns (uint256);

    /**
     * @dev Returns `true` if `account` has been granted all the given roles in the `ROOT_RESOURCE`.
     */
    function hasRootRoles(uint256 rolesBitmap, address account) external view returns (bool);

    /**
     * @dev Returns `true` if `account` has been granted all the given roles in `resource`.
     */
    function hasRoles(bytes32 resource, uint256 rolesBitmap, address account) external view returns (bool);

    /**
     * @dev Get if any of the roles in the given role bitmap has assignees.
     */
    function hasAssignees(bytes32 resource, uint256 roleBitmap) external view returns (bool);

    /**
     * @dev Get the no. of assignees for the roles in the given role bitmap.
     */
    function getAssigneeCount(bytes32 resource, uint256 roleBitmap) external view returns (uint256 counts, uint256 mask);

    /**
     * @dev Grants all roles in the given role bitmap to `account`.
     */
    function grantRoles(bytes32 resource, uint256 roleBitmap, address account) external returns (bool);

    /**
     * @dev Grants all roles in the given role bitmap to `account` in the ROOT_RESOURCE.
     */
    function grantRootRoles(uint256 roleBitmap, address account) external returns (bool);

    /**
     * @dev Revokes all roles in the given role bitmap from `account`.
     */
    function revokeRoles(bytes32 resource, uint256 roleBitmap, address account) external returns (bool);

    /**
     * @dev Revokes all roles in the given role bitmap from `account` in the ROOT_RESOURCE.
     */
    function revokeRootRoles(uint256 roleBitmap, address account) external returns (bool);
} 