// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";

import {StableTokenPriceOracle} from "../src/L2/StableTokenPriceOracle.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract TestStableTokenPriceOracle is Test {
    StableTokenPriceOracle oracle;
    MockERC20[] tokens;

    function setUp() external {
        oracle = new StableTokenPriceOracle();
        tokens = new MockERC20[](32);
        for (uint8 i; i < tokens.length; i++) {
            tokens[i] = new MockERC20("USD", i);
        }
    }

    function test_getTokenAmount() external view {
        assertEq(oracle.getTokenAmount(1, 1, tokens[1]), 1);
        assertEq(oracle.getTokenAmount(100, 2, tokens[0]), 1);
        assertEq(oracle.getTokenAmount(1, 0, tokens[2]), 100);

        assertEq(oracle.getTokenAmount(1000, 3, tokens[0]), 1);
        assertEq(oracle.getTokenAmount(1001, 3, tokens[0]), 2);
        assertEq(oracle.getTokenAmount(1999, 3, tokens[0]), 2);

        assertEq(oracle.getTokenAmount(1234_0000_0000, 8, tokens[0]), 1234);
    }
}
