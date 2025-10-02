// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @dev Interface for MigratedWrappedNameRegistry initialization and core functions
 */
interface IMigratedWrappedNameRegistry {
    function initialize(
        bytes calldata parentDnsEncodedName_,
        address ownerAddress_,
        uint256 ownerRoles_,
        address registrarAddress_
    ) external;
}
