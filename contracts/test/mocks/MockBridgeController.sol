// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

// used by ETHTLDResolver.test.ts
contract MockBridgeController is ERC721Holder {
    function hasRootRoles(uint256, address account) external view returns (bool) {
        // emulate L1BridgeController
        // appear as authorized ejector
        // but we hold the burned tokens
        return account == address(this);
    }
}
