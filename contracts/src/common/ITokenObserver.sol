// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/// @notice Observer pattern for events on existing tokens.
interface ITokenObserver {
    /// @notice Called when a token is renewed.
    ///
    /// @param tokenId The token ID of the token that was renewed.
    /// @param expires The new expiry date of the token.
    /// @param renewedBy The address that renewed the token.
    function onRenew(
        uint256 tokenId,
        uint64 expires,
        address renewedBy
    ) external;
}
