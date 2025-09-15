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
import {HalvingUtils} from "../src/common/HalvingUtils.sol";
import {StandardPricing} from "./StandardPricing.sol";

contract TestRentPriceOracle is Test {
    PermissionedRegistry ethRegistry;

    StandardRentPriceOracle rentPriceOracle;

    MockERC20 tokenUSDC;
    MockERC20 tokenDAI;

    address user = makeAddr("user");

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
        paymentRatios[0] = StandardPricing.ratioFromStable(tokenUSDC);
        paymentRatios[1] = StandardPricing.ratioFromStable(tokenDAI);

        rentPriceOracle = new StandardRentPriceOracle(
            address(this),
            ethRegistry,
            StandardPricing.getBaseRates(),
            StandardPricing.PREMIUM_PRICE_INITIAL,
            StandardPricing.PREMIUM_HALVING_PERIOD,
            StandardPricing.PREMIUM_PERIOD,
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
        assertEq(rentPriceOracle.isValid("a"), StandardPricing.RATE_1CP > 0);
        assertEq(rentPriceOracle.isValid("ab"), StandardPricing.RATE_2CP > 0);
        assertEq(rentPriceOracle.isValid("abc"), StandardPricing.RATE_3CP > 0);
        assertEq(rentPriceOracle.isValid("abce"), StandardPricing.RATE_4CP > 0);
        assertEq(
            rentPriceOracle.isValid("abcde"),
            StandardPricing.RATE_5CP > 0
        );
        assertEq(
            rentPriceOracle.isValid("abcdefghijklmnopqrstuvwxyz"),
            StandardPricing.RATE_5CP > 0
        );
    }

    function _testRentPrice(string memory label, uint256 rate) internal {
        uint256 base = rentPriceOracle.baseRate(label);
        assertEq(base, rate, "rate");
        _testRentPrice(label, rate, StandardPricing.SEC_PER_YEAR, tokenUSDC);
        _testRentPrice(label, rate, StandardPricing.SEC_PER_YEAR, tokenDAI);
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
        PaymentRatio memory t = StandardPricing.ratioFromStable(token);
        assertEq(
            base,
            Math.mulDiv(rate * dur, t.numer, t.denom, Math.Rounding.Ceil),
            token.name()
        );
    }

    function test_rentPrice_0() external {
        _testRentPrice("", 0);
    }
    function test_rentPrice_1() external {
        _testRentPrice("a", StandardPricing.RATE_1CP);
    }
    function test_rentPrice_2() external {
        _testRentPrice("ab", StandardPricing.RATE_2CP);
    }
    function test_rentPrice_3() external {
        _testRentPrice("abc", StandardPricing.RATE_3CP);
    }
    function test_rentPrice_4() external {
        _testRentPrice("abcd", StandardPricing.RATE_4CP);
    }
    function test_rentPrice_5() external {
        _testRentPrice("abcde", StandardPricing.RATE_5CP);
    }
    function test_rentPrice_long() external {
        _testRentPrice("abcdefghijklmnopqrstuvwxyz", StandardPricing.RATE_5CP);
    }

    function test_updateBaseRates() external {
        uint256[] memory rates = new uint256[](2);
        rates[0] = 1;
        rates[1] = 0;
        vm.expectEmit(false, false, false, true);
        emit StandardRentPriceOracle.BaseRatesChanged(rates);
        rentPriceOracle.updateBaseRates(rates);
        assertEq(rentPriceOracle.baseRate("a"), rates[0], "1");
        assertEq(rentPriceOracle.baseRate("ab"), rates[1], "2");
        assertEq(rentPriceOracle.baseRate("abcdef"), rates[1], "2+");
    }

    function test_updateBaseRates_disable() external {
        rentPriceOracle.updateBaseRates(new uint256[](0));
        for (uint256 i; i < 256; i++) {
            assertEq(rentPriceOracle.baseRate(new string(i)), 0);
        }
    }

    function test_updateBaseRates_notOwner() external {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        rentPriceOracle.updateBaseRates(new uint256[](1));
        vm.stopPrank();
    }

    function test_premiumPriceInitial() external view {
        assertEq(
            rentPriceOracle.premiumPriceInitial(),
            StandardPricing.PREMIUM_PRICE_INITIAL
        );
    }

    function test_premiumPriceAfter_start() external view {
        assertEq(
            rentPriceOracle.premiumPriceAfter(0),
            StandardPricing.PREMIUM_PRICE_INITIAL -
                HalvingUtils.halving(
                    StandardPricing.PREMIUM_PRICE_INITIAL,
                    StandardPricing.PREMIUM_HALVING_PERIOD,
                    StandardPricing.PREMIUM_PERIOD
                )
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

    function test_updatePremiumPricing() external {
        vm.expectEmit(false, false, false, false);
        emit StandardRentPriceOracle.PremiumPricingChanged(256000, 1, 8);
        rentPriceOracle.updatePremiumPricing(256000, 1, 8);
        assertEq(rentPriceOracle.premiumPriceAfter(0), 255000, "0");
        assertEq(rentPriceOracle.premiumPriceAfter(1), 127000, "1");
        assertEq(rentPriceOracle.premiumPriceAfter(2), 63000, "2");
        assertEq(rentPriceOracle.premiumPriceAfter(3), 31000, "3");
        assertEq(rentPriceOracle.premiumPriceAfter(4), 15000, "4");
        assertEq(rentPriceOracle.premiumPriceAfter(5), 7000, "5");
        assertEq(rentPriceOracle.premiumPriceAfter(6), 3000, "6");
        assertEq(rentPriceOracle.premiumPriceAfter(7), 1000, "7");
        assertEq(rentPriceOracle.premiumPriceAfter(8), 0, "8");
    }

    function test_updatePremiumPricing_disable() external {
        rentPriceOracle.updatePremiumPricing(0, 0, 0);
        assertEq(rentPriceOracle.premiumPriceAfter(0), 0, "after");
        assertEq(rentPriceOracle.premiumPriceInitial(), 0, "initial");
    }

    function test_updatePremiumPricing_notOwner() external {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        rentPriceOracle.updatePremiumPricing(0, 0, 0);
        vm.stopPrank();
    }
}
