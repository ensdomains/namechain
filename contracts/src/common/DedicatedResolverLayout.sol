// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/// @notice Storage layout of DedicatedResolver.
library DedicatedResolverLayout {
    uint256 constant SLOT_ADDRESSES = 0; // _addresses

    uint256 constant SLOT_TEXTS = 1; // _texts

    uint256 constant SLOT_CONTENTHASH = 2; // _contenthash

    uint256 constant SLOT_PUBKEY = 3; // _pubkeyX and _pubkeyY

    uint256 constant SLOT_ABIS = 5; // _abis

    uint256 constant SLOT_INTERFACES = 6; // _interfaces

    uint256 constant SLOT_PRIMARY = 7; // _primary
}
