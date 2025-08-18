// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

library PriceUtils {
    error AmountOverflow(uint256 amount, uint256 scale);

    function convertDecimals(
        uint256 inAmount,
        uint8 inDecimals,
        uint8 outDecimals
    ) internal pure returns (uint256) {
        if (outDecimals < inDecimals) {
            uint8 decimalDiff = inDecimals - outDecimals;
            uint256 scale = 10 ** decimalDiff;
            uint256 remainder = inAmount % scale;
            inAmount /= scale;
            // For precision loss mitigation, round up if there's a remainder
            // This ensures users don't pay less than intended due to truncation
            if (remainder > 0) {
                inAmount += 1;
            }
            return inAmount;
        } else if (outDecimals > inDecimals) {
            uint8 decimalDiff = outDecimals - inDecimals;
            uint256 scale = 10 ** decimalDiff;
            // Check for overflow: if usdAmount * 10^decimalDiff > type(uint256).max
            // Rearranged: if usdAmount > type(uint256).max / 10^decimalDiff
            if (inAmount > type(uint256).max / scale) {
                revert AmountOverflow(inAmount, scale);
            }
            return inAmount * scale;
        } else {
            return inAmount;
        }
    }

    uint256 constant PRECISION = 1e18;
    uint256 constant bit1 = 999989423469314432; // 0.5 ^ 1/65536 * (10 ** 18)
    uint256 constant bit2 = 999978847050491904; // 0.5 ^ 2/65536 * (10 ** 18)
    uint256 constant bit3 = 999957694548431104;
    uint256 constant bit4 = 999915390886613504;
    uint256 constant bit5 = 999830788931929088;
    uint256 constant bit6 = 999661606496243712;
    uint256 constant bit7 = 999323327502650752;
    uint256 constant bit8 = 998647112890970240;
    uint256 constant bit9 = 997296056085470080;
    uint256 constant bit10 = 994599423483633152;
    uint256 constant bit11 = 989228013193975424;
    uint256 constant bit12 = 978572062087700096;
    uint256 constant bit13 = 957603280698573696;
    uint256 constant bit14 = 917004043204671232;
    uint256 constant bit15 = 840896415253714560;
    uint256 constant bit16 = 707106781186547584;

    /// @dev Compute `initial / 2 ** (elapsed / half)`.
    /// @param initial The initial value.
    /// @param half The halving period.
    /// @param elapsed The elapsed duration.
    function halving(
        uint256 initial,
        uint256 half,
        uint256 elapsed
    ) internal pure returns (uint256) {
        if (initial == 0 || half == 0) return 0;
        if (elapsed == 0) return initial;
        uint256 x = (elapsed * PRECISION) / half;
        uint256 i = x / PRECISION;
        uint256 f = x - i * PRECISION;
        return _addFraction(initial >> i, (f << 16) / PRECISION);
    }

    function _addFraction(
        uint256 x,
        uint256 fraction
    ) private pure returns (uint256) {
        if (fraction & (1 << 0) != 0) {
            x = (x * bit1) / PRECISION;
        }
        if (fraction & (1 << 1) != 0) {
            x = (x * bit2) / PRECISION;
        }
        if (fraction & (1 << 2) != 0) {
            x = (x * bit3) / PRECISION;
        }
        if (fraction & (1 << 3) != 0) {
            x = (x * bit4) / PRECISION;
        }
        if (fraction & (1 << 4) != 0) {
            x = (x * bit5) / PRECISION;
        }
        if (fraction & (1 << 5) != 0) {
            x = (x * bit6) / PRECISION;
        }
        if (fraction & (1 << 6) != 0) {
            x = (x * bit7) / PRECISION;
        }
        if (fraction & (1 << 7) != 0) {
            x = (x * bit8) / PRECISION;
        }
        if (fraction & (1 << 8) != 0) {
            x = (x * bit9) / PRECISION;
        }
        if (fraction & (1 << 9) != 0) {
            x = (x * bit10) / PRECISION;
        }
        if (fraction & (1 << 10) != 0) {
            x = (x * bit11) / PRECISION;
        }
        if (fraction & (1 << 11) != 0) {
            x = (x * bit12) / PRECISION;
        }
        if (fraction & (1 << 12) != 0) {
            x = (x * bit13) / PRECISION;
        }
        if (fraction & (1 << 13) != 0) {
            x = (x * bit14) / PRECISION;
        }
        if (fraction & (1 << 14) != 0) {
            x = (x * bit15) / PRECISION;
        }
        if (fraction & (1 << 15) != 0) {
            x = (x * bit16) / PRECISION;
        }
        return x;
    }
}
