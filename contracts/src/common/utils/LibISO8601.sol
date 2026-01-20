// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

library LibISO8601 {
    /// @dev The timestamp is out of range.
    ///      Error selector: `0x09064f83`
    error TimestampOutOfRange(uint256 timestamp);

    function toISO8601(uint256 ts) internal pure returns (string memory result) {
        if (ts >= 253402300800) revert TimestampOutOfRange(ts);

        assembly {
            // Allocate memory
            result := mload(0x40)
            mstore(0x40, add(result, 0x40))
            mstore(result, 20)

            // Split timestamp
            let totalDays := div(ts, 86400)
            let secs := sub(ts, mul(totalDays, 86400))

            // Howard Hinnant date algorithm
            let z := add(totalDays, 719468)
            let era := div(z, 146097)
            let doe := sub(z, mul(era, 146097))
            let yoe := div(
                sub(sub(add(doe, div(doe, 36524)), div(doe, 1460)), div(doe, 146096)),
                365
            )
            let year := add(yoe, mul(era, 400))
            let doy := sub(doe, sub(add(mul(365, yoe), div(yoe, 4)), div(yoe, 100)))
            let mp := div(add(mul(5, doy), 2), 153)
            let day := add(sub(doy, div(add(mul(153, mp), 2), 5)), 1)
            let month := sub(add(mp, 3), mul(gt(mp, 9), 12))
            year := add(year, lt(month, 3))

            // Time (reuse secs)
            let hour := div(secs, 3600)
            secs := sub(secs, mul(hour, 3600))
            let minute := div(secs, 60)
            let second := sub(secs, mul(minute, 60))

            // Year YYYY
            let d := div(year, 1000)
            mstore8(add(result, 32), add(48, d))
            let d2 := div(year, 100)
            mstore8(add(result, 33), add(48, sub(d2, mul(d, 10))))
            d := div(year, 10)
            mstore8(add(result, 34), add(48, sub(d, mul(d2, 10))))
            mstore8(add(result, 35), add(48, sub(year, mul(d, 10))))
            mstore8(add(result, 36), 0x2d)

            // Month MM (1-12): gt is cheaper than div
            d := gt(month, 9)
            mstore8(add(result, 37), add(48, d))
            mstore8(add(result, 38), add(48, sub(month, mul(d, 10))))
            mstore8(add(result, 39), 0x2d)

            // Day DD (1-31)
            d := div(day, 10)
            mstore8(add(result, 40), add(48, d))
            mstore8(add(result, 41), add(48, sub(day, mul(d, 10))))
            mstore8(add(result, 42), 0x54)

            // Hour HH (0-23)
            d := div(hour, 10)
            mstore8(add(result, 43), add(48, d))
            mstore8(add(result, 44), add(48, sub(hour, mul(d, 10))))
            mstore8(add(result, 45), 0x3a)

            // Minute MM (0-59)
            d := div(minute, 10)
            mstore8(add(result, 46), add(48, d))
            mstore8(add(result, 47), add(48, sub(minute, mul(d, 10))))
            mstore8(add(result, 48), 0x3a)

            // Second SS (0-59)
            d := div(second, 10)
            mstore8(add(result, 49), add(48, d))
            mstore8(add(result, 50), add(48, sub(second, mul(d, 10))))
            mstore8(add(result, 51), 0x5a)
        }
    }
}
