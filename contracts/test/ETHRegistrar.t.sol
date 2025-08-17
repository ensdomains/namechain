// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {SimpleRegistryMetadata} from "../src/common/SimpleRegistryMetadata.sol";
import {ETHRegistrar, IETHRegistrar, IRegistry, PriceUtils, PRICE_DECIMALS, REGISTRATION_ROLE_BITMAP} from "../src/L2/ETHRegistrar.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockPermissionedRegistry} from "./mocks/MockPermissionedRegistry.sol";
import {EnhancedAccessControl, IEnhancedAccessControl, LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";

contract TestETHRegistrar is Test, ERC1155Holder {
    RegistryDatastore datastore;
    MockPermissionedRegistry ethRegistry;
    ETHRegistrar ethRegistrar;

    MockERC20 tokenUSDC;
    MockERC20 tokenDAI;

    address user1 = makeAddr("user1");
    //address user2 = makeAddr("user2");
    address beneficiary = makeAddr("beneficiary");

    uint64 constant SEC_PER_YEAR = 31_557_600; // 365.25

    uint256 constant PRICE_SCALE = 10 ** PRICE_DECIMALS;
    uint256 constant RATE_5_CHAR = (5 * PRICE_SCALE) / SEC_PER_YEAR;
    uint256 constant RATE_4_CHAR = (160 * PRICE_SCALE) / SEC_PER_YEAR;
    uint256 constant RATE_3_CHAR = (640 * PRICE_SCALE) / SEC_PER_YEAR;

    function setUp() external {
        // Set the timestamp to a future date to avoid timestamp related issues
        vm.warp(2_000_000_000);

        // Setup IRegistry(address(0)) and ethRegistrar
        datastore = new RegistryDatastore();

        ethRegistry = new MockPermissionedRegistry(
            datastore,
            new SimpleRegistryMetadata(),
            address(this),
            LibEACBaseRoles.ALL_ROLES
        );

        IERC20Metadata[] memory paymentTokens = new IERC20Metadata[](2);
        paymentTokens[0] = tokenUSDC = new MockERC20("USDC", "USDC", 6);
        paymentTokens[1] = tokenDAI = new MockERC20("DAI", "DAI", 18);

        ethRegistrar = new ETHRegistrar(
            ETHRegistrar.ConstructorArgs({
                ethRegistry: ethRegistry,
                beneficiary: beneficiary,
                minCommitmentAge: 1 minutes,
                maxCommitmentAge: 1 days,
                minRegistrationDuration: 28 days,
                gracePeriod: 90 days,
                baseRatePerCp: [0, 0, RATE_3_CHAR, RATE_4_CHAR, RATE_5_CHAR],
                premiumPeriod: 21 days,
                premiumHalvingPeriod: 1 days,
                premiumPriceInitial: 100_000_000 * PRICE_SCALE,
                paymentTokens: paymentTokens
            })
        );

        ethRegistry.grantRootRoles(
            LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_RENEW,
            address(ethRegistrar)
        );

        // Mint tokens to test accounts
        uint256 tokenAmount = 1000000 * 1e6; // 1M tokenUSDC
        tokenUSDC.mint(address(this), tokenAmount);
        tokenUSDC.mint(user1, tokenAmount);
        //tokenUSDC.mint(user2, tokenAmount);

        uint256 tokenDAIAmount = 1000000 * 1e18; // 1M tokenDAI
        tokenDAI.mint(address(this), tokenDAIAmount);
        tokenDAI.mint(user1, tokenDAIAmount);
        //tokenDAI.mint(user2, tokenDAIAmount);

        // Approve ethRegistrar to spend tokens
        tokenUSDC.approve(address(ethRegistrar), type(uint256).max);
        tokenDAI.approve(address(ethRegistrar), type(uint256).max);

        vm.prank(user1);
        tokenUSDC.approve(address(ethRegistrar), type(uint256).max);
        vm.prank(user1);
        tokenDAI.approve(address(ethRegistrar), type(uint256).max);

        // vm.prank(user2);
        // tokenUSDC.approve(address(ethRegistrar), type(uint256).max);
        // vm.prank(user2);
        // tokenDAI.approve(address(ethRegistrar), type(uint256).max);
    }

    function _expectEmit(bytes32 topic) internal {
        vm.expectEmit(false, false, false, false);
        assembly {
            log1(0, 0, topic)
        }
    }

    function test_Revert_constructor_emptyRange() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IETHRegistrar.MaxCommitmentAgeTooLow.selector
            )
        );
        ETHRegistrar.ConstructorArgs memory args;
        args.minCommitmentAge = args.maxCommitmentAge = 100;
        new ETHRegistrar(args);
    }

    function test_Revert_constructor_invalidRange() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IETHRegistrar.MaxCommitmentAgeTooLow.selector
            )
        );
        ETHRegistrar.ConstructorArgs memory args;
        args.minCommitmentAge = 100;
        args.maxCommitmentAge = 1;
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

    function _testRentPrice(
        string memory label,
        uint256 rentRate
    ) internal view {
        (uint256 base, uint256 premium) = ethRegistrar.rentPrice(
            label,
            SEC_PER_YEAR
        );
        uint256 expectedBase = rentRate * SEC_PER_YEAR;
        assertEq(base, expectedBase);
        assertEq(premium, 0);
        (base, ) = ethRegistrar.rentPrice(label, SEC_PER_YEAR, tokenUSDC);
        assertEq(
            base,
            PriceUtils.convertDecimals(
                expectedBase,
                PRICE_DECIMALS,
                tokenUSDC.decimals()
            )
        );
        (base, ) = ethRegistrar.rentPrice(label, SEC_PER_YEAR, tokenDAI);
        assertEq(
            base,
            PriceUtils.convertDecimals(
                expectedBase,
                PRICE_DECIMALS,
                tokenDAI.decimals()
            )
        );
    }

    function test_rentPrice_0() external {
        vm.expectRevert(
            abi.encodeWithSelector(IETHRegistrar.InvalidName.selector, "")
        );
        ethRegistrar.rentPrice("", 0);
    }
    function test_rentPrice_1() external {
        vm.expectRevert(
            abi.encodeWithSelector(IETHRegistrar.InvalidName.selector, "a")
        );
        ethRegistrar.rentPrice("a", 0);
    }
    function test_rentPrice_2() external {
        vm.expectRevert(
            abi.encodeWithSelector(IETHRegistrar.InvalidName.selector, "ab")
        );
        ethRegistrar.rentPrice("ab", 0);
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
        assertGt(ethRegistrar.premiumPriceAfter(dur - 1 hours), 0, "before");
        assertEq(ethRegistrar.premiumPriceAfter(dur), 0, "at");
        assertEq(ethRegistrar.premiumPriceAfter(dur + 1 hours), 0, "after");
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
        uint256 wait;
    }

    function _defaultRegisterArgs()
        internal
        view
        returns (RegisterArgs memory args)
    {
        args.label = "testname";
        args.sender = address(this);
        args.owner = address(this);
        args.paymentToken = tokenUSDC;
        args.duration = ethRegistrar.minRegistrationDuration();
        args.wait = ethRegistrar.minCommitmentAge() + 1;
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
            args.paymentToken
        );
        vm.stopPrank();
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
            "commitment"
        );
        vm.expectEmit(false, false, false, false);
        emit IETHRegistrar.CommitmentMade(commitment);
        ethRegistrar.commit(commitment);
        assertEq(ethRegistrar.commitments(commitment), block.timestamp, "time");
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
        assertTrue(ethRegistrar.isAvailable(args.label));
        this._register(args);
        assertFalse(ethRegistrar.isAvailable(args.label));
    }

    function test_register() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        _expectEmit(IETHRegistrar.NameRegistered.selector);
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
        vm.warp(block.timestamp + args.duration + ethRegistrar.gracePeriod());
        (, uint256 premium) = ethRegistrar.rentPrice(args.label, args.duration);
        assertEq(premium, ethRegistrar.premiumPriceAfter(0));
    }

    function test_register_premium_end() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        this._register(args);
        vm.warp(
            block.timestamp +
                args.duration +
                ethRegistrar.gracePeriod() +
                ethRegistrar.premiumPeriod()
        );
        (, uint256 premium) = ethRegistrar.rentPrice(args.label, args.duration);
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
                0, // current allowance
                base + premium // needed amount
            )
        );
        this._register(args);
    }

    function test_Revert_register_insufficientBalance() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        vm.prank(args.sender);
        tokenUSDC.transfer(user1, tokenUSDC.balanceOf(args.sender));
        (uint256 base, uint256 premium) = ethRegistrar.rentPrice(
            args.label,
            args.duration,
            args.paymentToken
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                args.sender,
                0, // current allowance
                base + premium // needed amount
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
        // vm.expectRevert(
        //     abi.encodeWithSelector(
        //         IETHRegistrar.NameAlreadyRegistered.selector,
        //         args.label
        //     )
        // );
        // this._register(args);
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

    function test_Revert_register_invalidOwner() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        args.owner = address(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IETHRegistrar.InvalidOwner.selector,
                args.owner
            )
        );
        this._register(args);
    }

    function test_renew() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        uint256 tokenId = this._register(args);
        uint256 expiry0 = ethRegistry.getExpiry(tokenId);
        _expectEmit(IETHRegistrar.NameRenewed.selector);
        ethRegistrar.renew(args.label, args.duration, args.paymentToken);
        assertEq(ethRegistry.getExpiry(tokenId), expiry0 + args.duration);
    }

    function test_renew_gracePeriod() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        uint256 tokenId = this._register(args);
        assertEq(ethRegistry.ownerOf(tokenId), args.owner, "owner0");
        assertFalse(ethRegistrar.isAvailable(args.label), "avail0");
        uint256 t = block.timestamp +
            args.duration +
            ethRegistrar.gracePeriod();
        vm.warp(t - 1);
        assertEq(ethRegistry.ownerOf(tokenId), address(0), "owner1");
        assertFalse(ethRegistrar.isAvailable(args.label), "avail1");
        vm.warp(t);
        assertTrue(ethRegistrar.isAvailable(args.label), "avail2");
    }

    function test_Revert_renew_nameNotRegistered() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        vm.expectRevert(
            abi.encodeWithSelector(
                IETHRegistrar.NameNotRegistered.selector,
                args.label
            )
        );
        ethRegistrar.renew(args.label, args.duration, args.paymentToken);
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
        ethRegistrar.renew(args.label, args.duration, args.paymentToken);
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
        assertEq(
            ethRegistrar.beneficiary(),
            beneficiary,
            "Beneficiary address not set correctly"
        );
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
        ethRegistrar.renew(args.label, args.duration, args.paymentToken);
        assertEq(args.paymentToken.balanceOf(beneficiary), balance0 + base);
    }

    function test_registry_bitmap() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        uint256 tokenId = this._register(args);
        uint256 resource = ethRegistry.testGetResourceFromTokenId(tokenId);
        assertTrue(
            ethRegistry.hasRoles(
                resource,
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                args.owner
            ),
            "ROLE_SET_SUBREGISTRY"
        );
        assertTrue(
            ethRegistry.hasRoles(
                resource,
                LibRegistryRoles.ROLE_SET_SUBREGISTRY_ADMIN,
                args.owner
            ),
            "ROLE_SET_SUBREGISTRY_ADMIN"
        );
        assertTrue(
            ethRegistry.hasRoles(
                resource,
                LibRegistryRoles.ROLE_SET_RESOLVER,
                args.owner
            ),
            "ROLE_SET_RESOLVER"
        );
        assertTrue(
            ethRegistry.hasRoles(
                resource,
                LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN,
                args.owner
            ),
            "ROLE_SET_RESOLVER_ADMIN"
        );
        assertTrue(
            ethRegistry.hasRoles(
                resource,
                REGISTRATION_ROLE_BITMAP,
                args.owner
            ),
            "REGISTRATION_ROLE_BITMAP"
        );
    }
}
