// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

pragma solidity ^0.8.20;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

interface IHCAFactory {
    function getGSAFromHCA(address hca) external view returns (address);
}

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
    IHCAFactory public constant HCA_FACTORY =
        IHCAFactory(0x0000000000000000000000000000000000000000);

    function _msgSender() internal view virtual override returns (address) {
        address gsa = HCA_FACTORY.getGSAFromHCA(msg.sender);
        if (gsa == address(0)) return msg.sender;
        return gsa;
    }
}
