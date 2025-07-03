// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;


abstract contract RegistryRolesMixin {
    uint256 internal constant ROLE_REGISTRAR = 0x1;
    uint256 internal constant ROLE_REGISTRAR_ADMIN = ROLE_REGISTRAR << 128;

    uint256 internal constant ROLE_RENEW = 0x10;
    uint256 internal constant ROLE_RENEW_ADMIN = ROLE_RENEW << 128;

    uint256 internal constant ROLE_SET_SUBREGISTRY = 0x100;
    uint256 internal constant ROLE_SET_SUBREGISTRY_ADMIN = ROLE_SET_SUBREGISTRY << 128;

    uint256 internal constant ROLE_SET_RESOLVER = 0x1000;
    uint256 internal constant ROLE_SET_RESOLVER_ADMIN = ROLE_SET_RESOLVER << 128;

    uint256 internal constant ROLE_SET_TOKEN_OBSERVER = 0x10000;
    uint256 internal constant ROLE_SET_TOKEN_OBSERVER_ADMIN = ROLE_SET_TOKEN_OBSERVER << 128;
}
