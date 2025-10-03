// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import {HCAEquivalence} from "./HCAEquivalence.sol";

/// @dev Replaces msg.sender
abstract contract HCAContext is Context, HCAEquivalence {
    /// @notice Returns either the account owner of an HCA or the original sender
    function _msgSender() internal view virtual override returns (address) {
        return _msgSenderWithHcaEquivalence();
    }
}
