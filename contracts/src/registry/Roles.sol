// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @dev This contract contains the roles for the registry.
 * 
 * We define everything here so that we can (a) avoid accidental clashes, and (b) define globally unique roles.
 */
abstract contract Roles {
    uint256 public constant ROLEBIT_SET_SUBREGISTRY = 1;
    uint256 public constant ROLEBIT_SET_SUBREGGISTRY_ADMIN = 1 << 128;
    uint256 public constant ROLE_SET_SUBREGISTRY = ROLEBIT_SET_SUBREGISTRY | ROLEBIT_SET_SUBREGGISTRY_ADMIN;

    uint256 public constant ROLEBIT_SET_RESOLVER = 1 << 1;
    uint256 public constant ROLEBIT_SET_RESOLVER_ADMIN = 1 << 129;
    uint256 public constant ROLE_SET_RESOLVER = ROLEBIT_SET_RESOLVER | ROLEBIT_SET_RESOLVER_ADMIN;

    uint256 public constant ROLEBIT_TLD_ISSUER = 1 << 2;
    uint256 public constant ROLEBIT_TLD_ISSUER_ADMIN = 1 << 130;
    uint256 public constant ROLE_TLD_ISSUER = ROLEBIT_TLD_ISSUER | ROLEBIT_TLD_ISSUER_ADMIN;

    uint256 public constant ROLEBIT_REGISTRAR = 1 << 3;
    uint256 public constant ROLEBIT_REGISTRAR_ADMIN = 1 << 131;
    uint256 public constant ROLE_REGISTRAR = ROLEBIT_REGISTRAR | ROLEBIT_REGISTRAR_ADMIN;

    uint256 public constant ROLEBIT_RENEW = 1 << 4;
    uint256 public constant ROLEBIT_RENEW_ADMIN = 1 << 132;
    uint256 public constant ROLE_RENEW = ROLEBIT_RENEW | ROLEBIT_RENEW_ADMIN;

    uint256 public constant ROLEBIT_RENEW_SETTER = 1 << 5;
    uint256 public constant ROLEBIT_RENEW_SETTER_ADMIN = 1 << 133;
    uint256 public constant ROLE_RENEW_SETTER = ROLEBIT_RENEW_SETTER | ROLEBIT_RENEW_SETTER_ADMIN;
}
