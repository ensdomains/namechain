// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {SimpleRegistryMetadata} from "../src/common/SimpleRegistryMetadata.sol";
import {PermissionedRegistry} from "../src/common/PermissionedRegistry.sol";
import {LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";
import {StandardRentPriceOracle, IRentPriceOracle} from "../src/L2/StandardRentPriceOracle.sol";
import {StableTokenPriceOracle} from "../src/L2/StableTokenPriceOracle.sol";
import {MockERC20, MockERC20Blacklist} from "../src/mocks/MockERC20.sol";

contract TestRentPriceOracle is Test {
    PermissionedRegistry ethRegistry;

    StandardRentPriceOracle rentPriceOracle;
    StableTokenPriceOracle tokenPriceOracle;

    MockERC20 tokenUSDC;
    MockERC20 tokenDAI;

    uint64 constant SEC_PER_YEAR = 31_557_600; // 365.25
    uint8 constant PRICE_DECIMALS = 12;
    uint256 constant PRICE_SCALE = 10 ** PRICE_DECIMALS;
    uint256 constant RATE_1CP = 0;
    uint256 constant RATE_2CP = 0;
    uint256 constant RATE_3CP = (640 * PRICE_SCALE) / SEC_PER_YEAR;
    uint256 constant RATE_4CP = (160 * PRICE_SCALE) / SEC_PER_YEAR;
    uint256 constant RATE_5CP = (5 * PRICE_SCALE) / SEC_PER_YEAR;

    function setUp() external {
        ethRegistry = new PermissionedRegistry(
            new RegistryDatastore(),
            new SimpleRegistryMetadata(),
            address(this),
            LibEACBaseRoles.ALL_ROLES
        );

        tokenPriceOracle = new StableTokenPriceOracle();

        IERC20Metadata[] memory paymentTokens = new IERC20Metadata[](2);
        paymentTokens[0] = tokenUSDC = new MockERC20("USDC", 6);
        paymentTokens[1] = tokenDAI = new MockERC20("DAI", 18);

        rentPriceOracle = new StandardRentPriceOracle(
            ethRegistry,
            PRICE_DECIMALS,
            [RATE_1CP, RATE_2CP, RATE_3CP, RATE_4CP, RATE_5CP],
            21 days, // premiumPeriod
            1 days, // premiumHavingPeriod
            100_000_000 * PRICE_SCALE, // premiumPriceInitial
            tokenPriceOracle,
            paymentTokens
        );

        vm.warp(rentPriceOracle.premiumPeriod()); // avoid timestamp issues
    }

    function test_supportsInterface() external view {
        assertTrue(
            ERC165Checker.supportsInterface(
                address(rentPriceOracle),
                type(IRentPriceOracle).interfaceId
            )
        );
    }

    function test_isPaymentToken() external view {
        assertTrue(rentPriceOracle.isPaymentToken(tokenUSDC), "USDC");
        assertTrue(rentPriceOracle.isPaymentToken(tokenDAI), "DAI");
        assertFalse(rentPriceOracle.isPaymentToken(IERC20Metadata(address(0))));
    }

    function test_isValid() external view {
        assertFalse(rentPriceOracle.isValid(""));
        assertEq(rentPriceOracle.isValid("a"), RATE_1CP > 0);
        assertEq(rentPriceOracle.isValid("ab"), RATE_2CP > 0);
        assertEq(rentPriceOracle.isValid("abc"), RATE_3CP > 0);
        assertEq(rentPriceOracle.isValid("abce"), RATE_4CP > 0);
        assertEq(rentPriceOracle.isValid("abcde"), RATE_5CP > 0);
        assertEq(
            rentPriceOracle.isValid("abcdefghijklmnopqrstuvwxyz"),
            RATE_5CP > 0
        );
    }

    function _testRentPrice(string memory label, uint256 rate) internal {
        uint256 base = rentPriceOracle.baseRate(label);
        assertEq(base, rate, "rate");
        _testRentPrice(label, rate, SEC_PER_YEAR, tokenUSDC);
        _testRentPrice(label, rate, SEC_PER_YEAR * 2, tokenDAI);
    }

    function _testRentPrice(
        string memory label,
        uint256 rate,
        uint64 dur,
        IERC20Metadata token
    ) internal {
        if (rate == 0) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IRentPriceOracle.NotRentable.selector,
                    label
                )
            );
        }
        (uint256 base, ) = rentPriceOracle.rentPrice(
            label,
            address(0),
            dur,
            token
        );
        assertEq(
            base,
            tokenPriceOracle.getTokenAmount(rate * dur, PRICE_DECIMALS, token),
            token.name()
        );
    }

    function test_rentPrice_0() external {
        _testRentPrice("", 0);
    }
    function test_rentPrice_1() external {
        _testRentPrice("a", 0);
    }
    function test_rentPrice_2() external {
        _testRentPrice("ab", 0);
    }
    function test_rentPrice_3() external {
        _testRentPrice("abc", RATE_3CP);
    }
    function test_rentPrice_4() external {
        _testRentPrice("abcd", RATE_4CP);
    }
    function test_rentPrice_5() external {
        _testRentPrice("abcde", RATE_5CP);
    }
    function test_rentPrice_long() external {
        _testRentPrice("abcdefghijklmnopqrstuvwxyz", RATE_5CP);
    }

    function test_premiumPriceAfter_start() external view {
        assertEq(
            rentPriceOracle.premiumPriceAfter(0),
            rentPriceOracle.premiumPriceInitial() -
                rentPriceOracle.premiumPriceOffset()
        );
    }

    function test_premiumPriceAfter_end() external view {
        uint64 dur = rentPriceOracle.premiumPeriod();
        uint64 dt = 1;
        assertGt(rentPriceOracle.premiumPriceAfter(dur - dt), 0, "before");
        assertEq(rentPriceOracle.premiumPriceAfter(dur), 0, "at");
        assertEq(rentPriceOracle.premiumPriceAfter(dur + dt), 0, "after");
    }

    function test_premiumPrice() external view {
        assertEq(rentPriceOracle.premiumPrice(0), 0, "0");
        assertEq(
            rentPriceOracle.premiumPrice(uint64(block.timestamp)),
            rentPriceOracle.premiumPriceAfter(0),
            "start"
        );
        assertEq(
            rentPriceOracle.premiumPrice(
                uint64(block.timestamp + rentPriceOracle.premiumPeriod())
            ),
            0,
            "end"
        );
    }
}
