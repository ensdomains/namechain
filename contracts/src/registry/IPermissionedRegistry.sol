// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IStandardRegistry} from "./IStandardRegistry.sol";

interface IPermissionedRegistry is IStandardRegistry {
    /**
     * @dev Event emitted when a token observer is set.
     */
    event TokenObserverSet(uint256 indexed tokenId, address observer);

    /**
     * @dev Sets a token observer for a token.
     * @param tokenId The token ID of the token to set the observer for.
     * @param observer The address of the observer to set.
     */
    function setTokenObserver(uint256 tokenId, address observer) external;

    /**
     * @dev Fetches the name data for a label.
     * @param label The label to fetch the name data for.
     * @return tokenId The token ID of the name.
     * @return expiry The expiry date of the name.
     * @return tokenIdVersion The token ID version of the name.
     */
    function getNameData(string calldata label) external view returns (uint256 tokenId, uint64 expiry, uint32 tokenIdVersion);
}