// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MockERC20} from "../src/mocks/MockERC20.sol";

import {PaymentRatio, DiscountPoint} from "../src/L2/StandardRentPriceOracle.sol";

library StandardPricing {
    uint64 constant SEC_PER_YEAR = 31_557_600; // 365.25
    uint64 constant SEC_PER_DAY = 86400; // 1 days

    uint8 constant PRICE_DECIMALS = 12;

    uint256 constant PRICE_SCALE = 10 ** PRICE_DECIMALS;

    uint256 constant RATE_1CP = 0;
    uint256 constant RATE_2CP = 0;
    uint256 constant RATE_3CP =
        (640 * PRICE_SCALE + SEC_PER_YEAR - 1) / SEC_PER_YEAR;
    uint256 constant RATE_4CP =
        (160 * PRICE_SCALE + SEC_PER_YEAR - 1) / SEC_PER_YEAR;
    uint256 constant RATE_5CP =
        (5 * PRICE_SCALE + SEC_PER_YEAR - 1) / SEC_PER_YEAR;

    uint256 constant PREMIUM_PRICE_INITIAL = 100_000_000 * PRICE_SCALE;
    uint64 constant PREMIUM_HALVING_PERIOD = SEC_PER_DAY;
    uint64 constant PREMIUM_PERIOD = 21 * SEC_PER_DAY;

    function getBaseRates() internal pure returns (uint256[] memory rates) {
        rates = new uint256[](5);
        rates[0] = RATE_1CP;
        rates[1] = RATE_2CP;
        rates[2] = RATE_3CP;
        rates[3] = RATE_4CP;
        rates[4] = RATE_5CP;
    }

    function getDiscountPoints()
        internal
        pure
        returns (DiscountPoint[] memory points)
    {
        // see: StandardRentPriceOracle.updateDiscountFunction()
        points = new DiscountPoint[](6);
        points[0] = DiscountPoint(SEC_PER_YEAR, 0);
        points[1] = DiscountPoint(SEC_PER_YEAR, /*********/ 100000000000000000); // 0.1 * StandardRentPriceOracle.DISCOUNT_SCALE
        points[2] = DiscountPoint(SEC_PER_YEAR, /*********/ 200000000000000000);
        points[3] = DiscountPoint(SEC_PER_YEAR * 2, /*****/ 287500000000000000);
        points[4] = DiscountPoint(SEC_PER_YEAR * 5, /*****/ 325000000000000000);
        points[5] = DiscountPoint(SEC_PER_YEAR * 15, /****/ 333333333333333334);
    }

    function ratioFromStable(
        MockERC20 token
    ) internal view returns (PaymentRatio memory) {
        uint8 d = token.decimals();
        if (d > PRICE_DECIMALS) {
            return PaymentRatio(token, uint128(10) ** (d - PRICE_DECIMALS), 1);
        } else {
            return PaymentRatio(token, 1, uint128(10) ** (PRICE_DECIMALS - d));
        }
    }
}
