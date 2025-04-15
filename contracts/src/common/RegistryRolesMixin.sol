// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;


abstract contract RegistryRolesMixin {
    uint256 internal constant ROLE_REGISTRAR = 1 << 0;
    uint256 internal constant ROLE_REGISTRAR_ADMIN = ROLE_REGISTRAR << 128;

    uint256 internal constant ROLE_RENEW = 1 << 1;
    uint256 internal constant ROLE_RENEW_ADMIN = ROLE_RENEW << 128;

    uint256 internal constant ROLE_SET_SUBREGISTRY = 1 << 2;
    uint256 internal constant ROLE_SET_SUBREGISTRY_ADMIN = ROLE_SET_SUBREGISTRY << 128;

    uint256 internal constant ROLE_SET_RESOLVER = 1 << 3;
    uint256 internal constant ROLE_SET_RESOLVER_ADMIN = ROLE_SET_RESOLVER << 128;

    uint256 internal constant ROLE_SET_TOKEN_OBSERVER = 1 << 4;
    uint256 internal constant ROLE_SET_TOKEN_OBSERVER_ADMIN = ROLE_SET_TOKEN_OBSERVER << 128;

    uint256 internal constant ROLE_SET_EJECTION_CONTROLLER = 1 << 5;
    uint256 internal constant ROLE_SET_EJECTION_CONTROLLER_ADMIN = ROLE_SET_EJECTION_CONTROLLER << 128;
}
