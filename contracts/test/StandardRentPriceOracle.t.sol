// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {SimpleRegistryMetadata} from "../src/common/SimpleRegistryMetadata.sol";
import {PermissionedRegistry, IRegistry} from "../src/common/PermissionedRegistry.sol";
import {LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";
import {StandardRentPriceOracle, PaymentRatio, IRentPriceOracle, DiscountPoint, DISCOUNT_SCALE} from "../src/L2/StandardRentPriceOracle.sol";
import {MockERC20, MockERC20Blacklist} from "../src/mocks/MockERC20.sol";

contract TestRentPriceOracle is Test, ERC1155Holder {
    PermissionedRegistry ethRegistry;

    StandardRentPriceOracle rentPriceOracle;

    MockERC20 tokenUSDC;
    MockERC20 tokenIdentity;

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
        tokenIdentity = new MockERC20("ID", PRICE_DECIMALS);

        PaymentRatio[] memory paymentRatios = new PaymentRatio[](2);
        paymentRatios[0] = _fromStablecoin(tokenUSDC);
        paymentRatios[1] = _fromStablecoin(tokenIdentity);

        DiscountPoint[] memory discountPoints = new DiscountPoint[](6);
        discountPoints[0] = DiscountPoint(SEC_PER_YEAR, 0);
        discountPoints[1] = DiscountPoint(SEC_PER_YEAR * 2, 50e15); // 0.05 * DISCOUNT_SCALE
        discountPoints[2] = DiscountPoint(SEC_PER_YEAR * 3, 100e15);
        discountPoints[3] = DiscountPoint(SEC_PER_YEAR * 5, 175e15);
        discountPoints[4] = DiscountPoint(SEC_PER_YEAR * 10, 250e15);
        discountPoints[5] = DiscountPoint(SEC_PER_YEAR * 25, 300e15);

        rentPriceOracle = new StandardRentPriceOracle(
            address(this),
            ethRegistry,
            [RATE_1CP, RATE_2CP, RATE_3CP, RATE_4CP, RATE_5CP],
            discountPoints,
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
        assertTrue(rentPriceOracle.isPaymentToken(tokenIdentity), "ID");
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

    function _testRentPrice(uint256 n, uint256 rate) internal {
        string memory label = new string(n);
        uint256 base = rentPriceOracle.baseRate(label);
        assertEq(base, rate, "rate");
        _testRentPrice(label, rate, SEC_PER_YEAR, tokenUSDC); // duration must be before initial
        _testRentPrice(label, rate, SEC_PER_YEAR, tokenIdentity); // discount or price will be reduced
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
        assertEq(
            base,
            Math.mulDiv(rate * dur, t.numer, t.denom, Math.Rounding.Ceil),
            token.name()
        );
    }

    function test_rentPrice_0() external {
        _testRentPrice(0, 0);
    }
    function test_rentPrice_1() external {
        _testRentPrice(1, 0);
    }
    function test_rentPrice_2() external {
        _testRentPrice(2, 0);
    }
    function test_rentPrice_3() external {
        _testRentPrice(3, RATE_3CP);
    }
    function test_rentPrice_4() external {
        _testRentPrice(4, RATE_4CP);
    }
    function test_rentPrice_5() external {
        _testRentPrice(5, RATE_5CP);
    }
    function test_rentPrice_long() external {
        _testRentPrice(255, RATE_5CP);
    }

    function _testDiscount(uint64 t, uint256 value) internal view {
        assertEq(rentPriceOracle.integratedDiscount(t) / t, value);
    }

    function test_discountAfter_start() external view {
        assertEq(rentPriceOracle.integratedDiscount(0), 0);
    }
    function test_discountAfter_1year() external view {
        _testDiscount(SEC_PER_YEAR, 0);
    }
    function test_discountAfter_2years() external view {
        _testDiscount(SEC_PER_YEAR * 2, 50e15);
    }
    function test_discountAfter_3years() external view {
        _testDiscount(SEC_PER_YEAR * 3, 100e15);
    }
    function test_discountAfter_5years() external view {
        _testDiscount(SEC_PER_YEAR * 5, 175e15);
    }
    function test_discountAfter_10years() external view {
        _testDiscount(SEC_PER_YEAR * 10, 250e15);
    }
    function test_discountAfter_30years() external view {
        _testDiscount(SEC_PER_YEAR * 30, 300e15);
    }
    function test_discountAfter_end() external view {
        _testDiscount(type(uint64).max, 300e15);
    }

    function _testDiscountedRentPrice(
        string memory label,
        uint64 dur0,
        uint64 dur1
    ) internal {
        ethRegistry.register(
            label,
            address(this),
            IRegistry(address(0)),
            address(0),
            0,
            uint64(block.timestamp) + dur0
        );
        uint256 base0 = rentPriceOracle.baseRate(label) * dur1;
        (uint256 base1, ) = rentPriceOracle.rentPrice(
            label,
            address(this),
            dur1,
            tokenIdentity
        );
        assertLt(base1, base0, "discounted");
        assertEq(
            base1,
            base0 -
                Math.mulDiv(
                    base0,
                    rentPriceOracle.integratedDiscount(dur0 + dur1) -
                        rentPriceOracle.integratedDiscount(dur0),
                    DISCOUNT_SCALE * dur1
                ),
            "discount"
        );
    }

    function _testDiscountedPermutations(uint256 n) internal {
        bytes memory buf = new bytes(n);
        for (uint64 i = 1; i < 3; i++) {
            buf[0] = bytes1(uint8(i));
            for (uint64 j = 1; j < 10; j++) {
                buf[1] = bytes1(uint8(j));
                _testDiscountedRentPrice(
                    string(buf),
                    SEC_PER_YEAR * i,
                    SEC_PER_YEAR * j
                );
            }
        }
    }

    function test_discountedRentPrice_3() external {
        _testDiscountedPermutations(3);
    }
    function test_discountedRentPrice_4() external {
        _testDiscountedPermutations(4);
    }
    function test_discountedRentPrice_5() external {
        _testDiscountedPermutations(5);
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
