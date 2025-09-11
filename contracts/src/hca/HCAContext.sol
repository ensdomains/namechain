// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

pragma solidity ^0.8.25;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import {IHCAFactoryBasic} from "./IHCAFactoryBasic.sol";

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract HCAContext is Context {
    /// @notice The HCA factory contract
    IHCAFactoryBasic public immutable HCA_FACTORY;

    /// @notice Initializes the HCA factory contract
    /// @param hcaFactory_ The address of the HCA factory contract
    constructor(address hcaFactory_) {
        HCA_FACTORY = IHCAFactoryBasic(hcaFactory_);
    }

    /// @notice Returns either the account owner of an HCA or the original sender
    function _msgSender() internal view virtual override returns (address) {
        address accountOwner = HCA_FACTORY.getAccountOwner(msg.sender);
        if (accountOwner == address(0)) return msg.sender;
        return accountOwner;
    }
}
