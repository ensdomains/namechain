// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @dev Interface for MigratedWrappedNameRegistry initialization and core functions
 */
interface IMigratedWrappedNameRegistry {
    function initialize(
        bytes calldata _parentDnsEncodedName,
        address _ownerAddress,
        uint256 _ownerRoles,
        address _registrarAddress
    ) external;
}