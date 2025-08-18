// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ITokenPriceOracle} from "../L2/ITokenPriceOracle.sol";
import {PriceUtils} from "../common/PriceUtils.sol";

/// @notice Oracle that assumes every token is a stable coin.
contract MockStableTokenPriceOracle is ITokenPriceOracle {
    function getTokenAmount(
        uint256 price,
        uint8 decimals,
        IERC20Metadata token
    ) external view returns (uint256) {
        return PriceUtils.convertDecimals(price, decimals, token.decimals());
    }
}
