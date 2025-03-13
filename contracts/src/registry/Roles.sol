// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @dev This contract contains the roles for the registry.
 * 
 * We define everything here so that we can (a) avoid accidental clashes, and (b) define globally unique roles.
 */
abstract contract Roles {
    uint256 public constant ROLE_SET_SUBREGISTRY = 1 << 0;
    uint256 public constant ROLE_SET_RESOLVER = 1 << 1;
    uint256 public constant ROLE_TLD_ISSUER = 1 << 2;
    uint256 public constant ROLE_REGISTRAR = 1 << 3;
    uint256 public constant ROLE_RENEW = 1 << 4;
    uint256 public constant ROLE_RENEWER_ADMIN = 1 << 5;
    uint256 public constant ROLE_PARENT = 1 << 6;
}
