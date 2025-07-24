// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @dev Observer pattern for events on existing tokens.
 */
interface ITokenObserver {
    /**
     * @dev Called when a token is renewed.
     * @param tokenId The token ID of the token that was renewed.
     * @param expires The new expiry date of the token.
     * @param renewedBy The address that renewed the token.
     */
    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external;

    /**
     * @dev Called when a token is relinquished.
     * @param tokenId The token ID of the token that was relinquished.
     * @param relinquishedBy The address that relinquished the token.
     */
    function onRelinquish(uint256 tokenId, address relinquishedBy) external;
}
