// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @dev This contract contains the roles for the registry.
 * 
 * We define everything here so that we can (a) avoid accidental clashes, and (b) define globally unique roles.
 */
abstract contract Roles {
    uint8 public constant ROLE_SET_SUBREGISTRY = 2;
    uint8 public constant ROLE_SET_RESOLVER = 3;
    uint8 public constant ROLE_TLD_ISSUER = 4;
    uint8 public constant ROLE_REGISTRAR_ROLE = 5;
    uint8 public constant ROLE_RENEW = 6;
    
    // default roles which are granted to the owner of a token
    uint256 public ROLE_BITMAP_TOKEN_OWNER_DEFAULT = (1 << ROLE_SET_SUBREGISTRY) | (1 << ROLE_SET_RESOLVER);
}
