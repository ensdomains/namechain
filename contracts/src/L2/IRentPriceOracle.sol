// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice Interface for pricing registration and renewals.
/// @dev Interface selector: `0x53b53cee`.
interface IRentPriceOracle {
    /// @notice `label` has no rent price.
    /// @dev Error selector: `0x58832032`
    error NotRentable(string label);

    /// @notice `paymentToken` is not supported for payment.
    /// @dev Error selector: `0x02e2ae9e`
    error PaymentTokenNotSupported(IERC20Metadata paymentToken);

    /// @notice Check if `paymentToken` is accepted for payment.
    /// @param paymentToken The ERC20 to check.
    /// @return `true` if `paymentToken` is accepted.
    function isPaymentToken(
        IERC20Metadata paymentToken
    ) external view returns (bool);

    /// @notice Check if a `label` is valid.
    /// @param label The name.
    /// @return `true` if the `label` is valid.
    function isValid(string memory label) external view returns (bool);

    /// @notice Get rent price for `label`.
    /// @dev Reverts `PaymentTokenNotSupported` or `NotRentable`.
    /// @param label The name.
    /// @param owner The new owner address.
    /// @param duration The duration to price, in seconds.
    /// @param paymentToken The ERC-20 to use.
    /// @return base The base price, relative to `paymentToken`.
    /// @return premium The premium price, relative to `paymentToken`.
    function rentPrice(
        string memory label,
        address owner,
        uint64 duration,
        IERC20Metadata paymentToken
    ) external view returns (uint256 base, uint256 premium);
}
