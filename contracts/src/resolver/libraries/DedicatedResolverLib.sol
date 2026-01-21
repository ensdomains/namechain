// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/// @notice Storage layout and roles for DedicatedResolver.
library DedicatedResolverLib {
    struct Storage {
        mapping(uint256 coinType => bytes addressBytes) addresses;
        mapping(string key => string value) texts;
        bytes contenthash;
        bytes32[2] pubkey;
        mapping(uint256 contentType => bytes data) abis;
        mapping(bytes4 interfaceId => address implementer) interfaces;
        string name;
    }

    uint256 internal constant NAMED_SLOT = uint256(keccak256("eth.ens.storage.DedicatedResolver"));

    uint256 internal constant SLOT_ADDRESSES = NAMED_SLOT; // addresses
    uint256 internal constant SLOT_TEXTS = NAMED_SLOT + 1; // texts
    uint256 internal constant SLOT_CONTENTHASH = NAMED_SLOT + 2; // contenthash
    uint256 internal constant SLOT_PUBKEY = NAMED_SLOT + 3; // pubkey[2]
    uint256 internal constant SLOT_ABIS = NAMED_SLOT + 5; // abis
    uint256 internal constant SLOT_INTERFACES = NAMED_SLOT + 6; // interfaces
    uint256 internal constant SLOT_NAME = NAMED_SLOT + 7; // name

    uint256 internal constant ROLE_SET_ADDR = 1 << 0;
    uint256 internal constant ROLE_SET_ADDR_ADMIN = ROLE_SET_ADDR << 128;

    uint256 internal constant ROLE_SET_TEXT = 1 << 4;
    uint256 internal constant ROLE_SET_TEXT_ADMIN = ROLE_SET_TEXT << 128;

    uint256 internal constant ROLE_SET_CONTENTHASH = 1 << 8;
    uint256 internal constant ROLE_SET_CONTENTHASH_ADMIN = ROLE_SET_CONTENTHASH << 128;

    uint256 internal constant ROLE_SET_PUBKEY = 1 << 12;
    uint256 internal constant ROLE_SET_PUBKEY_ADMIN = ROLE_SET_PUBKEY << 128;

    uint256 internal constant ROLE_SET_ABI = 1 << 16;
    uint256 internal constant ROLE_SET_ABI_ADMIN = ROLE_SET_ABI << 128;

    uint256 internal constant ROLE_SET_INTERFACE = 1 << 20;
    uint256 internal constant ROLE_SET_INTERFACE_ADMIN = ROLE_SET_INTERFACE << 128;

    uint256 internal constant ROLE_SET_NAME = 1 << 24;
    uint256 internal constant ROLE_SET_NAME_ADMIN = ROLE_SET_NAME << 128;

    uint256 internal constant ROLE_UPGRADE = 1 << 28;
    uint256 internal constant ROLE_UPGRADE_ADMIN = ROLE_UPGRADE << 128;

    function textResource(string memory key) internal pure returns (uint256) {
        return uint256(keccak256(bytes(key)));
    }

    function addrResource(uint256 coinType) internal pure returns (uint256 resource) {
        assembly ("memory-safe") {
            mstore(0, coinType)
            resource := keccak256(0, 32)
        }
    }
}
