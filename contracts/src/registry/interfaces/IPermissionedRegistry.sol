// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IEnhancedAccessControl} from "../../access-control/interfaces/IEnhancedAccessControl.sol";

import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {IStandardRegistry} from "./IStandardRegistry.sol";

interface IPermissionedRegistry is IStandardRegistry, IEnhancedAccessControl {
    ////////////////////////////////////////////////////////////////////////
    // Functions
    ////////////////////////////////////////////////////////////////////////

    /// @notice Get the latest owner of a token.
    ///         If the token was burned, returns null.
    /// @param tokenId The token ID to query.
    /// @return The latest owner address.
    function latestOwnerOf(uint256 tokenId) external view returns (address);

    /**
     * @dev Fetches the name data for a label.
     * @param label The label to fetch the name data for.
     * @return tokenId The token ID of the name.
     * @return entry The entry data for the name.
     */
    function getNameData(
        string calldata label
    ) external view returns (uint256 tokenId, IRegistryDatastore.Entry memory entry);

    /// @notice Get datastore `Entry` from `anyId`.
    /// @param anyId The labelhash, token ID, or resource.
    /// @return The datastore entry.
    function getEntry(uint256 anyId) external view returns (IRegistryDatastore.Entry memory);

    /// @notice Get `resource` from `anyId`.
    /// @param anyId The labelhash, token ID, or resource.
    /// @return The resource.
    function getResource(uint256 anyId) external view returns (uint256);

    /// @notice Get `tokenId` from `anyId`.
    /// @param anyId The labelhash, token ID, or resource.
    /// @return The token ID.
    function getTokenId(uint256 anyId) external view returns (uint256);
}
