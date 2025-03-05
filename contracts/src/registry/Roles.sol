// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @dev This contract contains the roles for the registry.
 * 
 * We define everything here so that we can (a) avoid accidental clashes, and (b) define globally unique roles.
 */
abstract contract Roles {
    uint8 public constant TLD_ISSUER_ROLE = 1;
    uint8 public constant REGISTRAR_ROLE = 2;
    uint8 public constant RENEW_ROLE = 3;
}
