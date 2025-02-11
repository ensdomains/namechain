// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistry} from "./IRegistry.sol";

/**
 * @dev Interface for the ETH Registrar.
 */
interface IETHRegistrar {
    /**
     * @dev Returns true if the specified name is available for registration.
     *
     * @param tokenId The ID of the name to check.
     *
     * @return True if the name is available, false otherwise.
     */
    function available(uint256 tokenId) external view returns (bool);

    /**
     * @dev Register a name.
     *
     * @param label The label of the name to register.
     * @param owner The address of the owner of the name.
     * @param subregistry The registry to use for the registration.
     * @param flags The flags to use for the registration.
     * @param expires The expiration timestamp of the registration.
     *
     * @return The ID of the newly registered name.
     */
    function register(
      string calldata label, address owner, IRegistry subregistry, uint96 flags, uint64 expires
    ) external returns (uint256);

    /**
     * @dev Renew a name.
     *
     * @param tokenId The ID of the name to renew.
     * @param expires The expiration timestamp of the renewal.
     */
    function renew(uint256 tokenId, uint64 expires) external;
}
