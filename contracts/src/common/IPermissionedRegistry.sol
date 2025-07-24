// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IStandardRegistry} from "./IStandardRegistry.sol";
import {ITokenObserver} from "./ITokenObserver.sol";

interface IPermissionedRegistry is IStandardRegistry {
    /**
     * @dev Event emitted when a token observer is set.
     */
    event TokenObserverSet(uint256 indexed tokenId, address observer);

    /**
     * @dev Sets a token observer for a token.
     * @param tokenId The token ID of the token to set the observer for.
     * @param observer The observer to set.
     */
    function setTokenObserver(uint256 tokenId, ITokenObserver observer) external;

    /**
     * @dev Fetches the name data for a label.
     * @param label The label to fetch the name data for.
     * @return tokenId The token ID of the name.
     * @return expiry The expiry date of the name.
     * @return tokenIdVersion The token ID version of the name.
     */
    function getNameData(string calldata label) external view returns (uint256 tokenId, uint64 expiry, uint32 tokenIdVersion);    


    /**
     * @dev Fetches the access control resource ID for a given token ID.
     * @param tokenId The token ID to fetch the resource ID for.
     * @return The access control resource ID for the token ID.
     */
    function getTokenIdResource(uint256 tokenId) external pure returns (bytes32);


    /**
     * @dev Fetches the token ID for a given access control resource ID.
     * @param resource The access control resource ID to fetch the token ID for.
     * @return The token ID for the resource ID.
     */
    function getResourceTokenId(bytes32 resource) external view returns (uint256);



    /**
     * @dev Fetches the number of assignees for a given role bitmap.
     * @param tokenId The token ID to fetch the assignee count for.
     * @param roleBitmap The role bitmap to fetch the assignee count for.
     * @return counts The number of assignees for the role bitmap.
     * @return mask The mask of the role bitmap.
     */
    function getRoleAssigneeCount(uint256 tokenId, uint256 roleBitmap) external view returns (uint256 counts, uint256 mask);
}