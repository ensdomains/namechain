// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @title Errors
 * @dev Common error definitions used across multiple contracts
 */

/**
 * @dev Thrown when an operation requires a valid owner but receives the zero address
 */
error InvalidOwner();

/**
 * @dev Thrown when a caller is not authorized to perform the requested operation
 * @param caller The address that attempted the unauthorized operation
 */
error UnauthorizedCaller(address caller);