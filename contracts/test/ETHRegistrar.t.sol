// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors, IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {MockERC20, MockERC20Blacklist, MockERC20VoidReturn, MockERC20FalseReturn} from "../src/mocks/MockERC20.sol";
import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {SimpleRegistryMetadata} from "../src/common/SimpleRegistryMetadata.sol";
import {StableTokenPriceOracle} from "../src/L2/StableTokenPriceOracle.sol";
import {ETHRegistrar, IETHRegistrar, IRegistry, REGISTRATION_ROLE_BITMAP} from "../src/L2/ETHRegistrar.sol";
import {PermissionedRegistry} from "../src/common/PermissionedRegistry.sol";
import {LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";
import {NameUtils} from "../src/common/NameUtils.sol";

contract TestETHRegistrar is Test {
    RegistryDatastore datastore;
    PermissionedRegistry ethRegistry;
    StableTokenPriceOracle tokenPriceOracle;
    ETHRegistrar ethRegistrar;

    MockERC20 tokenUSDC;
    MockERC20 tokenDAI;
    MockERC20Blacklist tokenBlack;
    MockERC20VoidReturn tokenVoid;
    MockERC20FalseReturn tokenFalse;

    address user = makeAddr("user1");
    address beneficiary = makeAddr("beneficiary");

    uint64 constant SEC_PER_YEAR = 31_557_600; // 365.25

    uint8 constant PRICE_DECIMALS = 12;
    uint256 constant PRICE_SCALE = 10 ** PRICE_DECIMALS;
    uint256 constant RATE_5_CHAR = (5 * PRICE_SCALE) / SEC_PER_YEAR;
    uint256 constant RATE_4_CHAR = (160 * PRICE_SCALE) / SEC_PER_YEAR;
    uint256 constant RATE_3_CHAR = (640 * PRICE_SCALE) / SEC_PER_YEAR;

    function setUp() external {
        vm.warp(2_000_000_000); // avoid timestamp issues

        datastore = new RegistryDatastore();

        ethRegistry = new PermissionedRegistry(
            datastore,
            new SimpleRegistryMetadata(),
            address(this),
            LibEACBaseRoles.ALL_ROLES
        );

        tokenPriceOracle = new StableTokenPriceOracle();

        IERC20Metadata[] memory paymentTokens = new IERC20Metadata[](5);
        paymentTokens[0] = tokenUSDC = new MockERC20("USDC", 6);
        paymentTokens[1] = tokenDAI = new MockERC20("DAI", 18);
        paymentTokens[2] = tokenBlack = new MockERC20Blacklist();
        paymentTokens[3] = tokenVoid = new MockERC20VoidReturn();
        paymentTokens[4] = tokenFalse = new MockERC20FalseReturn();

        ethRegistrar = new ETHRegistrar(
            ETHRegistrar.ConstructorArgs({
                ethRegistry: ethRegistry,
                beneficiary: beneficiary,
                minCommitmentAge: 1 minutes,
                maxCommitmentAge: 1 days,
                minRegistrationDuration: 28 days,
                priceDecimals: PRICE_DECIMALS,
                baseRatePerCp: [0, 0, RATE_3_CHAR, RATE_4_CHAR, RATE_5_CHAR],
                premiumPeriod: 21 days,
                premiumHalvingPeriod: 1 days,
                premiumPriceInitial: 100_000_000 * PRICE_SCALE,
                tokenPriceOracle: tokenPriceOracle,
                paymentTokens: paymentTokens
            })
        );

        ethRegistry.grantRootRoles(
            LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_RENEW,
            address(ethRegistrar)
        );

        for (uint256 i; i < paymentTokens.length; i++) {
            MockERC20 token = MockERC20(address(paymentTokens[i]));
            token.mint(user, 1e9 * 10 ** token.decimals());
            vm.prank(user);
            token.approve(address(ethRegistrar), type(uint256).max);
        }
    }

    function test_Revert_constructor_emptyRange() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IETHRegistrar.MaxCommitmentAgeTooLow.selector
            )
        );
        ETHRegistrar.ConstructorArgs memory args;
        args.minCommitmentAge = args.maxCommitmentAge = 1;
        new ETHRegistrar(args);
    }

    function test_Revert_constructor_invalidRange() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IETHRegistrar.MaxCommitmentAgeTooLow.selector
            )
        );
        ETHRegistrar.ConstructorArgs memory args;
        args.minCommitmentAge = 1;
        new ETHRegistrar(args);
    }

    function test_isValid() external view {
        assertFalse(ethRegistrar.isValid(""));
        assertFalse(ethRegistrar.isValid("a"));
        assertFalse(ethRegistrar.isValid("ab"));

        assertTrue(ethRegistrar.isValid("abc"));
        assertTrue(ethRegistrar.isValid("abce"));
        assertTrue(ethRegistrar.isValid("abcde"));
        assertTrue(ethRegistrar.isValid("abcdefghijklmnopqrstuvwxyz"));
    }

    function _testRentPrice(string memory label, uint256 rate) internal view {
        uint256 base = ethRegistrar.basePrice(label, 1);
        assertEq(base, rate, "rate");
        uint64 dur = SEC_PER_YEAR;
        base = ethRegistrar.basePrice(label, dur);
        assertEq(base, rate * dur, "year");
        (base, ) = ethRegistrar.rentPrice(label, dur, tokenUSDC);
        assertEq(
            base,
            tokenPriceOracle.getTokenAmount(
                rate * dur,
                PRICE_DECIMALS,
                tokenUSDC
            ),
            "USDC"
        );
        (base, ) = ethRegistrar.rentPrice(label, dur, tokenDAI);
        assertEq(
            base,
            tokenPriceOracle.getTokenAmount(
                rate * dur,
                PRICE_DECIMALS,
                tokenDAI
            ),
            "DAI"
        );
    }

    function test_rentPrice_0() external {
        string memory label;
        vm.expectRevert(
            abi.encodeWithSelector(IETHRegistrar.NoRentPrice.selector, label)
        );
        ethRegistrar.basePrice(label, 0);
    }
    function test_rentPrice_1() external {
        string memory label = "a";
        vm.expectRevert(
            abi.encodeWithSelector(IETHRegistrar.NoRentPrice.selector, label)
        );
        ethRegistrar.basePrice(label, 0);
    }
    function test_rentPrice_2() external {
        string memory label = "ab";
        vm.expectRevert(
            abi.encodeWithSelector(IETHRegistrar.NoRentPrice.selector, label)
        );
        ethRegistrar.basePrice(label, 0);
    }
    function test_rentPrice_3() external view {
        _testRentPrice("abc", RATE_3_CHAR);
    }
    function test_rentPrice_4() external view {
        _testRentPrice("abcd", RATE_4_CHAR);
    }
    function test_rentPrice_5() external view {
        _testRentPrice("abcde", RATE_5_CHAR);
    }
    function test_rentPrice_long() external view {
        _testRentPrice("abcdefghijklmnopqrstuvwxyz", RATE_5_CHAR);
    }

    function test_premiumPriceAfter_start() external view {
        assertEq(
            ethRegistrar.premiumPriceAfter(0),
            ethRegistrar.premiumPriceInitial() -
                ethRegistrar.premiumPriceOffset()
        );
    }

    function test_premiumPriceAfter_end() external view {
        uint64 dur = ethRegistrar.premiumPeriod();
        uint64 dt = 1;
        assertGt(ethRegistrar.premiumPriceAfter(dur - dt), 0, "before");
        assertEq(ethRegistrar.premiumPriceAfter(dur), 0, "at");
        assertEq(ethRegistrar.premiumPriceAfter(dur + dt), 0, "after");
    }

    struct RegisterArgs {
        address sender;
        string label;
        address owner;
        bytes32 secret;
        IRegistry subregistry;
        address resolver;
        uint64 duration;
        IERC20Metadata paymentToken;
        bytes32 referer;
        uint256 wait;
    }

    function _defaultRegisterArgs()
        internal
        view
        returns (RegisterArgs memory args)
    {
        args.label = "testname";
        args.sender = user;
        args.owner = user;
        args.paymentToken = tokenUSDC;
        args.duration = ethRegistrar.minRegistrationDuration();
        args.wait = ethRegistrar.minCommitmentAge() + 1;
    }

    function _makeCommitment(
        RegisterArgs memory args
    ) internal view returns (bytes32) {
        return
            ethRegistrar.makeCommitment(
                args.label,
                args.owner,
                args.secret,
                args.subregistry,
                args.resolver,
                args.duration
            );
    }

    function _register(
        RegisterArgs memory args
    ) external returns (uint256 tokenId) {
        bytes32 commitment = _makeCommitment(args);
        vm.startPrank(args.sender);
        ethRegistrar.commit(commitment);
        vm.warp(block.timestamp + args.wait);
        tokenId = ethRegistrar.register(
            args.label,
            args.owner,
            args.secret,
            args.subregistry,
            args.resolver,
            args.duration,
            args.paymentToken,
            args.referer
        );
        vm.stopPrank();
    }

    function _renew(RegisterArgs memory args) external {
        vm.prank(args.sender);
        ethRegistrar.renew(
            args.label,
            args.duration,
            args.paymentToken,
            args.referer
        );
    }

    function test_commit() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        bytes32 commitment = _makeCommitment(args);
        assertEq(
            commitment,
            keccak256(
                abi.encode(
                    args.label,
                    args.owner,
                    args.secret,
                    args.subregistry,
                    args.resolver,
                    args.duration
                )
            ),
            "hash"
        );
        vm.expectEmit(false, false, false, false);
        emit IETHRegistrar.CommitmentMade(commitment);
        ethRegistrar.commit(commitment);
        assertEq(
            ethRegistrar.commitmentAt(commitment),
            block.timestamp,
            "time"
        );
    }

    function test_Revert_commit_unexpiredCommitment() external {
        bytes32 commitment = bytes32(uint256(1));
        ethRegistrar.commit(commitment);
        vm.expectRevert(
            abi.encodeWithSelector(
                IETHRegistrar.UnexpiredCommitmentExists.selector,
                commitment
            )
        );
        ethRegistrar.commit(commitment);
    }

    function test_isAvailable() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        assertTrue(ethRegistrar.isAvailable(args.label), "before");
        this._register(args);
        assertFalse(ethRegistrar.isAvailable(args.label), "after");
    }

    function test_register() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        vm.expectEmit(false, false, false, false);
        bytes32 topic = IETHRegistrar.NameRegistered.selector;
        assembly {
            log2(0, 0, topic, 0)
        }
        uint256 tokenId = this._register(args);
        assertEq(ethRegistry.ownerOf(tokenId), args.owner, "owner");
        assertEq(
            ethRegistry.getExpiry(tokenId),
            uint64(block.timestamp) + args.duration,
            "expiry"
        );
    }

    function test_register_premium_start() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        this._register(args);
        vm.warp(block.timestamp + args.duration);
        uint256 premium = ethRegistrar.premiumPrice(args.label);
        assertEq(premium, ethRegistrar.premiumPriceAfter(0));
    }

    function test_register_premium_end() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        this._register(args);
        vm.warp(block.timestamp + args.duration + ethRegistrar.premiumPeriod());
        uint256 premium = ethRegistrar.premiumPrice(args.label);
        assertEq(premium, 0);
    }

    function test_Revert_register_insufficientAllowance() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        vm.prank(args.sender);
        tokenUSDC.approve(address(ethRegistrar), 0);
        (uint256 base, uint256 premium) = ethRegistrar.rentPrice(
            args.label,
            args.duration,
            args.paymentToken
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(ethRegistrar), // spender
                0, // allowance
                base + premium // needed
            )
        );
        this._register(args);
    }

    function test_Revert_register_insufficientBalance() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        tokenUSDC.nuke(args.sender);
        (uint256 base, uint256 premium) = ethRegistrar.rentPrice(
            args.label,
            args.duration,
            args.paymentToken
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                args.sender, // sender
                0, // allowance
                base + premium // needed
            )
        );
        this._register(args);
    }

    function test_Revert_register_commitmentTooNew() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        uint256 dt = 1;
        args.wait = ethRegistrar.minCommitmentAge() - dt;
        uint256 t = block.timestamp + args.wait;
        vm.expectRevert(
            abi.encodeWithSelector(
                IETHRegistrar.CommitmentTooNew.selector,
                _makeCommitment(args),
                t + dt,
                t
            )
        );
        this._register(args);
    }

    function test_Revert_register_commitmentTooOld() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        uint256 dt = 1;
        args.wait = ethRegistrar.maxCommitmentAge() + dt;
        uint256 t = block.timestamp + args.wait;
        vm.expectRevert(
            abi.encodeWithSelector(
                IETHRegistrar.CommitmentTooOld.selector,
                _makeCommitment(args),
                t - dt,
                t
            )
        );
        this._register(args);
    }

    function test_Revert_register_nameNotAvailable() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        this._register(args);
        vm.expectRevert(
            abi.encodeWithSelector(
                IETHRegistrar.NameAlreadyRegistered.selector,
                args.label
            )
        );
        this._register(args);
    }

    function test_Revert_register_durationTooShort() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        args.duration = ethRegistrar.minRegistrationDuration() - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IETHRegistrar.DurationTooShort.selector,
                args.duration,
                ethRegistrar.minRegistrationDuration()
            )
        );
        this._register(args);
    }

    function test_Revert_register_nullOwner() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        args.owner = address(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC1155Errors.ERC1155InvalidReceiver.selector,
                args.owner
            )
        );
        this._register(args);
    }

    function test_renew() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        uint256 tokenId = this._register(args);
        uint256 expiry0 = ethRegistry.getExpiry(tokenId);
        vm.expectEmit(false, false, false, false);
        bytes32 topic = IETHRegistrar.NameRenewed.selector;
        assembly {
            log2(0, 0, topic, 0)
        }
        this._renew(args);
        assertEq(ethRegistry.getExpiry(tokenId), expiry0 + args.duration);
    }

    function test_Revert_renew_nameNotRegistered() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IETHRegistrar.NameNotRegistered.selector,
                args.label
            )
        );
        this._renew(args);
    }

    function test_Revert_renew_insufficientAllowance() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        this._register(args);
        vm.prank(args.sender);
        tokenUSDC.approve(address(ethRegistrar), 0);
        (uint256 base, ) = ethRegistrar.rentPrice(
            args.label,
            args.duration,
            args.paymentToken
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(ethRegistrar),
                0,
                base
            )
        );
        this._renew(args);
    }

    function test_supportsInterface() external view {
        assertTrue(
            ERC165Checker.supportsInterface(
                address(ethRegistrar),
                type(IETHRegistrar).interfaceId
            )
        );
    }

    function test_beneficiary_set() external view {
        assertEq(ethRegistrar.beneficiary(), beneficiary);
    }

    function test_beneficiary_register() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        (uint256 base, ) = ethRegistrar.rentPrice(
            args.label,
            args.duration,
            args.paymentToken
        );
        uint256 balance0 = args.paymentToken.balanceOf(beneficiary);
        this._register(args);
        assertEq(args.paymentToken.balanceOf(beneficiary), balance0 + base);
    }

    function test_beneficiary_renew() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        this._register(args);
        uint256 balance0 = args.paymentToken.balanceOf(beneficiary);
        (uint256 base, ) = ethRegistrar.rentPrice(
            args.label,
            args.duration,
            args.paymentToken
        );
        this._renew(args);
        assertEq(args.paymentToken.balanceOf(beneficiary), balance0 + base);
    }

    function test_registry_bitmap() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        uint256 tokenId = this._register(args);
        assertTrue(
            ethRegistry.hasRoles(
                NameUtils.getCanonicalId(tokenId),
                REGISTRATION_ROLE_BITMAP,
                args.owner
            )
        );
    }

    function test_blacklist_user() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        tokenBlack.setBlacklisted(user, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                MockERC20Blacklist.Blacklisted.selector,
                user
            )
        );
        args.paymentToken = tokenBlack;
        this._register(args);
        args.paymentToken = tokenUSDC;
        this._register(args);
    }

    function test_blacklist_beneficiary() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        tokenBlack.setBlacklisted(ethRegistrar.beneficiary(), true);
        vm.expectRevert(
            abi.encodeWithSelector(
                MockERC20Blacklist.Blacklisted.selector,
                ethRegistrar.beneficiary()
            )
        );
        args.paymentToken = tokenBlack;
        this._register(args);
        args.paymentToken = tokenUSDC;
        this._register(args);
    }

    function test_noReturn_accepted_with_SafeERC20() public {
        RegisterArgs memory args = _defaultRegisterArgs();
        args.paymentToken = tokenVoid;
        this._register(args);
    }

    function test_falseReturn_rejected_with_SafeERC20() public {
        RegisterArgs memory args = _defaultRegisterArgs();
        args.paymentToken = tokenFalse;
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20.SafeERC20FailedOperation.selector,
                tokenFalse
            )
        );
        this._register(args);
    }
}
