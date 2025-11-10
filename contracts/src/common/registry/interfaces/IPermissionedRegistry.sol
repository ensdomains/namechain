// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IEnhancedAccessControl} from "../../access-control/interfaces/IEnhancedAccessControl.sol";

import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {IStandardRegistry} from "./IStandardRegistry.sol";
import {ITokenObserver} from "./ITokenObserver.sol";

interface IPermissionedRegistry is IStandardRegistry, IEnhancedAccessControl {
    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    /**
     * @dev Event emitted when a token observer is set.
     */
    event TokenObserverSet(uint256 indexed tokenId, address observer);

    ////////////////////////////////////////////////////////////////////////
    // Functions
    ////////////////////////////////////////////////////////////////////////

    /// @notice Sets a token observer.
    /// @param anyId The labelhash, token ID, or resource.
    /// @param observer The new observer.
    function setTokenObserver(uint256 anyId, ITokenObserver observer) external;

    /// @notice Get a token observer.
    /// @param anyId The labelhash, token ID, or resource.
    /// @return observer The current observer.
    function getTokenObserver(uint256 anyId) external view returns (ITokenObserver);

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
}
