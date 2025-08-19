// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ITokenPriceOracle} from "./ITokenPriceOracle.sol";

/// @notice Oracle that assumes every token is a stable coin.
contract StableTokenPriceOracle is ITokenPriceOracle {
    function getTokenAmount(
        uint256 price,
        uint8 decimals,
        IERC20Metadata token
    ) external view returns (uint256) {
        uint256 d = token.decimals();
        if (d == decimals) return price;
        return
            d > decimals
                ? price * 10 ** (d - decimals)
                : Math.ceilDiv(price, 10 ** (decimals - d)); // both panic on overflow
    }
}
