// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface ITokenPriceOracle {
    function getTokenAmount(
        uint256 price,
		uint8 decimals,
        IERC20Metadata token
    ) external view returns (uint256);
}
