// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {SimpleRegistryMetadata} from "../src/common/SimpleRegistryMetadata.sol";
import {PermissionedRegistry} from "../src/common/PermissionedRegistry.sol";
import {LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";
import {StandardRentPriceOracle, PaymentRatio, IRentPriceOracle, Ownable} from "../src/L2/StandardRentPriceOracle.sol";
import {MockERC20, MockERC20Blacklist} from "../src/mocks/MockERC20.sol";

contract TestRentPriceOracle is Test {
    PermissionedRegistry ethRegistry;

    StandardRentPriceOracle rentPriceOracle;

    MockERC20 tokenUSDC;
    MockERC20 tokenDAI;

    address user = makeAddr("user");

    uint64 constant SEC_PER_YEAR = 31_557_600; // 365.25
    uint8 constant PRICE_DECIMALS = 12;
    uint256 constant PRICE_SCALE = 10 ** PRICE_DECIMALS;
    uint256 constant RATE_1CP = 0;
    uint256 constant RATE_2CP = 0;
    uint256 constant RATE_3CP = (640 * PRICE_SCALE) / SEC_PER_YEAR;
    uint256 constant RATE_4CP = (160 * PRICE_SCALE) / SEC_PER_YEAR;
    uint256 constant RATE_5CP = (5 * PRICE_SCALE) / SEC_PER_YEAR;

    function _fromStablecoin(
        MockERC20 token
    ) internal view returns (PaymentRatio memory) {
        uint8 d = token.decimals();
        if (d > PRICE_DECIMALS) {
            return PaymentRatio(token, uint128(10) ** (d - PRICE_DECIMALS), 1);
        } else {
            return PaymentRatio(token, 1, uint128(10) ** (PRICE_DECIMALS - d));
        }
    }

    function setUp() external {
        ethRegistry = new PermissionedRegistry(
            new RegistryDatastore(),
            new SimpleRegistryMetadata(),
            address(this),
            LibEACBaseRoles.ALL_ROLES
        );

        tokenUSDC = new MockERC20("USDC", 6);
        tokenDAI = new MockERC20("DAI", 18);

        PaymentRatio[] memory paymentRatios = new PaymentRatio[](2);
        paymentRatios[0] = _fromStablecoin(tokenUSDC);
        paymentRatios[1] = _fromStablecoin(tokenDAI);

        rentPriceOracle = new StandardRentPriceOracle(
            address(this),
            ethRegistry,
            [RATE_1CP, RATE_2CP, RATE_3CP, RATE_4CP, RATE_5CP],
            21 days, // premiumPeriod
            1 days, // premiumHavingPeriod
            100_000_000 * PRICE_SCALE, // premiumPriceInitial
            paymentRatios
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
        assertFalse(rentPriceOracle.isPaymentToken(IERC20(address(0))));
    }

    function test_updatePaymentToken_remove() external {
        IERC20 paymentToken = tokenUSDC;
        assertTrue(rentPriceOracle.isPaymentToken(paymentToken), "before");
        vm.expectEmit(true, false, false, false);
        emit IRentPriceOracle.PaymentTokenRemoved(paymentToken);
        rentPriceOracle.updatePaymentToken(paymentToken, 0, 0);
        assertFalse(rentPriceOracle.isPaymentToken(paymentToken), "after");
    }

    function test_updatePaymentToken_add() external {
        IERC20 paymentToken = IERC20(address(1));
        assertFalse(rentPriceOracle.isPaymentToken(paymentToken), "before");
        vm.expectEmit(true, false, false, false);
        emit IRentPriceOracle.PaymentTokenAdded(paymentToken);
        rentPriceOracle.updatePaymentToken(paymentToken, 1, 1);
        assertTrue(rentPriceOracle.isPaymentToken(paymentToken), "after");
    }

    function test_updatePaymentToken_invalidRatio() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                StandardRentPriceOracle.InvalidRatio.selector
            )
        );
        rentPriceOracle.updatePaymentToken(tokenUSDC, 0, 1);
    }

    function test_updatePaymentToken_notOwner() external {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        rentPriceOracle.updatePaymentToken(tokenUSDC, 0, 0); // remove
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        rentPriceOracle.updatePaymentToken(tokenUSDC, 1, 1); // add
        vm.stopPrank();
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
        MockERC20 token
    ) internal {
        if (rate == 0) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IRentPriceOracle.NotValid.selector,
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
        PaymentRatio memory t = _fromStablecoin(token);
        assertEq(base, Math.mulDiv(rate * dur, t.numer, t.denom), token.name());
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
