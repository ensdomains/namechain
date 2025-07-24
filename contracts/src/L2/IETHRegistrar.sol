// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistry} from "../common/IRegistry.sol";
import {IPriceOracle} from "@ens/contracts/ethregistrar/IPriceOracle.sol";

/**
 * @dev Interface for the ETH Registrar.
 */
interface IETHRegistrar {
    /**
     * @dev Emitted when a name is registered.
     *
     * @param name The name that was registered.
     * @param owner The address of the owner of the name.
     * @param subregistry The registry used for the registration.
     * @param resolver The resolver used for the registration.
     * @param duration The duration of the registration.
     * @param tokenId The ID of the newly registered name.
     */
    event NameRegistered(
        string name, address owner, IRegistry subregistry, address resolver, uint64 duration, uint256 tokenId
    );

    /**
     * @dev Emitted when a name is renewed.
     *
     * @param name The name that was renewed.
     * @param duration The duration of the renewal.
     * @param tokenId The ID of the renewed name.
     * @param newExpiry The new expiry of the name.
     */
    event NameRenewed(string name, uint64 duration, uint256 tokenId, uint64 newExpiry);

    /**
     * @dev Emitted when a commitment is made.
     *
     * @param commitment The commitment that was made.
     */
    event CommitmentMade(bytes32 commitment);

    /**
     * @dev Returns true if the specified name is available for registration.
     *
     * @param name The name to check.
     *
     * @return True if the name is available, false otherwise.
     */
    function available(string calldata name) external view returns (bool);

    /**
     * @dev Check if a name is valid.
     * @param name The name to check.
     * @return True if the name is valid, false otherwise.
     */
    function valid(string memory name) external view returns (bool);

    /**
     * @dev Get the price to register or renew a name.
     *
     * @param name The name to get the price for.
     * @param duration The duration of the registration or renewal.
     * @return price The price to register or renew the name.
     */
    function rentPrice(string memory name, uint256 duration) external view returns (IPriceOracle.Price memory price);

    /**
     * @dev Make a commitment for a name.
     *
     * @param name The name to commit.
     * @param owner The address of the owner of the name.
     * @param secret The secret of the name.
     * @param subregistry The registry to use for the commitment.
     * @param resolver The resolver to use for the commitment.
     * @param duration The duration of the commitment.
     * @return The commitment.
     */
    function makeCommitment(
        string calldata name,
        address owner,
        bytes32 secret,
        address subregistry,
        address resolver,
        uint64 duration
    ) external pure returns (bytes32);

    /**
     * @dev Commit a commitment.
     *
     * @param commitment The commitment to commit.
     */
    function commit(bytes32 commitment) external;

    /**
     * @dev Register a name.
     *
     * @param name The name to register.
     * @param owner The address of the owner of the name.
     * @param secret The secret of the name.
     * @param subregistry The registry to use for the registration.
     * @param resolver The resolver to use for the registration.
     * @param duration The duration of the registration.
     *
     * @return The ID of the newly registered name.
     */
    function register(
        string calldata name,
        address owner,
        bytes32 secret,
        IRegistry subregistry,
        address resolver,
        uint64 duration
    ) external payable returns (uint256);

    /**
     * @dev Renew a name.
     *
     * @param name The name to renew.
     * @param duration The duration of the renewal.
     */
    function renew(string calldata name, uint64 duration) external payable;
}
