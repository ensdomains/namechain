// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/// @notice Storage layout and roles for OwnedResolver.
library OwnedResolverLib {
    struct Storage {
        mapping(bytes32 node => bytes) aliases;
    }

    uint256 internal constant NAMED_SLOT = uint256(keccak256("eth.ens.storage.OwnedResolver"));
}
