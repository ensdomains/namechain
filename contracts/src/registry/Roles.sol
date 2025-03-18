// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @dev This contract contains the roles for the registry.
 *
 * These roles and admin roles are defined according to what's expected by the EnhancedAccessControl contract, namely that 
 * the admin role for a given user role equals that role shifted left by 128 bits.
 */
abstract contract Roles {
    uint256 public constant ROLE_SET_SUBREGISTRY = 1;
    uint256 public constant ROLE_SET_SUBREGISTRY_ADMIN = ROLE_SET_SUBREGISTRY << 128;

    uint256 public constant ROLE_SET_RESOLVER = 1 << 1;
    uint256 public constant ROLE_SET_RESOLVER_ADMIN = ROLE_SET_RESOLVER << 128;

    uint256 public constant ROLE_TLD_ISSUER = 1 << 2;
    uint256 public constant ROLE_TLD_ISSUER_ADMIN = ROLE_TLD_ISSUER << 128;

    uint256 public constant ROLE_REGISTRAR = 1 << 3;
    uint256 public constant ROLE_REGISTRAR_ADMIN = ROLE_REGISTRAR << 128;

    uint256 public constant ROLE_RENEW = 1 << 4;
    uint256 public constant ROLE_RENEW_ADMIN = ROLE_RENEW << 128;
}
