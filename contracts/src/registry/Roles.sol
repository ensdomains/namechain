// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @dev This contract contains the roles for the registry.
 * 
 * We define everything here so that we can (a) avoid accidental clashes, and (b) define globally unique roles.
 */
abstract contract Roles {
    /*
    NOTE: DEFAULT_ADMIN_ROLE is 1, so all other roles are a bit positions 2 to 256
    */
    uint256 public constant ROLE_SET_SUBREGISTRY = 1 << 1;
    uint256 public constant ROLE_SET_RESOLVER = 1 << 2;
    uint256 public constant ROLE_TLD_ISSUER = 1 << 3;
    uint256 public constant ROLE_REGISTRAR = 1 << 4;
    uint256 public constant ROLE_RENEW = 1 << 5;
    uint256 public constant ROLE_RENEWER_ADMIN = 1 << 6;
    uint256 public constant ROLE_PARENT = 1 << 7;
    
    // default roles which are granted to the owner of a token
    uint256 public ROLE_BITMAP_TOKEN_OWNER_DEFAULT = ROLE_SET_SUBREGISTRY | ROLE_SET_RESOLVER;
    uint256 public ROLE_BITMAP_REGISTRAR_DEFAULT = ROLE_REGISTRAR | ROLE_RENEW;
}
