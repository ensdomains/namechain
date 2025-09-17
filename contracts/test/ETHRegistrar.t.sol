// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors, IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {MockERC20, MockERC20Blacklist} from "../src/mocks/MockERC20.sol";
import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {SimpleRegistryMetadata} from "../src/common/SimpleRegistryMetadata.sol";
import {PermissionedRegistry} from "../src/common/PermissionedRegistry.sol";
import {StandardRentPriceOracle, IRentPriceOracle, PaymentRatio} from "../src/L2/StandardRentPriceOracle.sol";
import {ETHRegistrar, IETHRegistrar, IRegistry, REGISTRATION_ROLE_BITMAP, ROLE_SET_ORACLE} from "../src/L2/ETHRegistrar.sol";
import {EnhancedAccessControl, IEnhancedAccessControl, LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";

contract TestETHRegistrar is Test, ERC1155Holder {
    RegistryDatastore datastore;
    MockPermissionedRegistry registry;
    ETHRegistrar registrar;
    StablePriceOracle priceOracle;
    MockERC20 usdc;
    MockERC20 dai;

    address user1 = address(0x1);
    address user2 = address(0x2);
    address beneficiary = address(0x3);
    uint256 constant MIN_COMMITMENT_AGE = 60; // 1 minute
    uint256 constant MAX_COMMITMENT_AGE = 86400; // 1 day
    // Realistic ENS pricing from https://docs.ens.domains/registry/eth 
    // Using per-second rates calculated with high precision to avoid rounding to zero
    // 5+ character names: $5/year ÷ 31,536,000 seconds = ~158.5 × 10^-9 USD/sec
    // 4 character names: $160/year ÷ 31,536,000 seconds = ~5.072 × 10^-6 USD/sec  
    // 3 character names: $640/year ÷ 31,536,000 seconds = ~20.289 × 10^-6 USD/sec
    
    // Scale up to avoid integer division rounding to zero
    // Using nanodollars per second (1e9 scaling) then converting to 6-decimal USD
    uint256 constant PRICE_5_CHAR = 158; // ~158.5 nanodollars/sec → multiply by duration to get total 
    uint256 constant PRICE_4_CHAR = 5072; // ~5072 nanodollars/sec
    uint256 constant PRICE_3_CHAR = 20289; // ~20289 nanodollars/sec
    uint64 constant REGISTRATION_DURATION = 365 days;
    bytes32 constant SECRET = bytes32(uint256(1234567890));

    // Use LibRegistryRoles constants instead of hardcoded values
    bytes32 constant ROOT_RESOURCE = 0;

    function setUp() public {
        // Set the timestamp to a future date to avoid timestamp related issues
        vm.warp(2_000_000_000);

        // Create mock tokens
        usdc = new MockERC20("USDC", "USDC", 6);
        dai = new MockERC20("DAI", "DAI", 18);

        // Setup StablePriceOracle with length-based pricing
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(dai);
        
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 6; // USDC
        decimals[1] = 18; // DAI
        
        // Price array: [5+char, 4char, 3char, 2char, 1char]  
        uint256[] memory rentPrices = new uint256[](5);
        rentPrices[0] = PRICE_5_CHAR; // 5+ chars
        rentPrices[1] = PRICE_4_CHAR; // 4 chars
        rentPrices[2] = PRICE_3_CHAR; // 3 chars  
        rentPrices[3] = 0; // 2 chars (not supported)
        rentPrices[4] = 0; // 1 char (not supported)
        
        priceOracle = new StablePriceOracle(tokens, decimals, rentPrices);

        // Setup registry and registrar
        datastore = new RegistryDatastore();
        // Use a defined ALL_ROLES value for deployer roles
        uint256 deployerRoles = LibEACBaseRoles.ALL_ROLES;
        registry = new MockPermissionedRegistry(datastore, new SimpleRegistryMetadata(), address(this), deployerRoles);
        registrar = new ETHRegistrar(address(registry), priceOracle, MIN_COMMITMENT_AGE, MAX_COMMITMENT_AGE, beneficiary);
        registry.grantRootRoles(LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_RENEW, address(registrar));
        
        // Mint tokens to test accounts
        uint256 tokenAmount = 1000000 * 1e6; // 1M USDC
        usdc.mint(address(this), tokenAmount);
        usdc.mint(user1, tokenAmount);
        usdc.mint(user2, tokenAmount);
        
        uint256 daiAmount = 1000000 * 1e18; // 1M DAI
        dai.mint(address(this), daiAmount);
        dai.mint(user1, daiAmount);
        dai.mint(user2, daiAmount);

        // Approve registrar to spend tokens
        usdc.approve(address(registrar), type(uint256).max);
        dai.approve(address(registrar), type(uint256).max);
        
        vm.prank(user1);
        usdc.approve(address(registrar), type(uint256).max);
        vm.prank(user1);
        dai.approve(address(registrar), type(uint256).max);
        
        vm.prank(user2);
        usdc.approve(address(registrar), type(uint256).max);
        vm.prank(user2);
        dai.approve(address(registrar), type(uint256).max);
    }


    // Helper function to register a name with USDC (default test token)
    function _registerName(
        string memory name,
        address owner,
        bytes32 secret,
        IRegistry subregistry,
        address resolver,
        uint64 duration
    ) internal returns (uint256 tokenId) {
        bytes32 commitment = registrar.makeCommitment(name, owner, secret, address(subregistry), resolver, duration);
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        tokenId = registrar.register(name, owner, secret, subregistry, resolver, duration, address(usdc));
    }

    function test_valid() public view {
        assertTrue(registrar.valid("abc"));
        assertTrue(registrar.valid("test"));
        assertTrue(registrar.valid("longername"));
        
        assertFalse(registrar.valid("ab"));
        assertFalse(registrar.valid("a"));
        assertFalse(registrar.valid(""));
    }

    function test_Revert_maxCommitmentAgeTooLow() public {
        // Try to create a registrar with maxCommitmentAge <= minCommitmentAge
        uint256 invalidMinAge = 100;
        uint256 invalidMaxAge = 100; // Equal to minAge, should revert
        
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.MaxCommitmentAgeTooLow.selector));
        new ETHRegistrar(address(registry), priceOracle, invalidMinAge, invalidMaxAge, beneficiary);
        // Try with max age less than min age
        invalidMaxAge = 99; // Less than minAge, should revert
        
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.MaxCommitmentAgeTooLow.selector));
        new ETHRegistrar(address(registry), priceOracle, invalidMinAge, invalidMaxAge, beneficiary);
    }

    function test_available() public {
        string memory name = "testname";
        assertTrue(registrar.available(name));
        
        // Register the name with USDC
        bytes32 commitment = registrar.makeCommitment(
            name, 
            address(this), 
            SECRET, 
            address(registry),
            address(0), // resolver
            REGISTRATION_DURATION
        );
        registrar.commit(commitment);
        
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        registrar.register(
            name, 
            address(this), 
            SECRET,
            registry,
            address(0), // resolver
            REGISTRATION_DURATION,
            address(usdc)
        );
        
        // Verify name is no longer available
        assertFalse(registrar.available(name));
    }

    function test_rentPrice() public view {
        string memory name = "testname";
        IPriceOracle.Price memory price = registrar.rentPrice(name, REGISTRATION_DURATION);
        
        uint256 expectedPrice = PRICE_5_CHAR * REGISTRATION_DURATION;
        assertEq(price.base, expectedPrice);
        assertEq(price.premium, 0);
    }

    function test_checkPrice() public view {
        string memory name = "testname";
        
        uint256 expectedBasePrice = PRICE_5_CHAR * REGISTRATION_DURATION;
        
        // Check USDC price (6 decimals) - should match base price since both use 6 decimals
        uint256 usdcAmount = registrar.checkPrice(name, REGISTRATION_DURATION, address(usdc));
        assertEq(usdcAmount, expectedBasePrice);
        
        // Check DAI price (18 decimals) - should be scaled up by 10^12
        uint256 daiAmount = registrar.checkPrice(name, REGISTRATION_DURATION, address(dai));
        assertEq(daiAmount, expectedBasePrice * 1e12);
    }

    function test_makeCommitment() public view {
        string memory name = "testname";
        address owner = address(this);
        bytes32 secret = bytes32(uint256(1));
        address subregistry = address(registry);
        address resolver = address(0);
        uint64 duration = REGISTRATION_DURATION;
        
        bytes32 commitment = registrar.makeCommitment(name, owner, secret, subregistry, resolver, duration);
        
        bytes32 expectedCommitment = keccak256(
            abi.encode(
                name,
                owner,
                secret,
                subregistry,
                resolver,
                duration
            )
        );
        
        assertEq(commitment, expectedCommitment);
    }

    function test_Revert_constructor_invalidRange() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IETHRegistrar.MaxCommitmentAgeTooLow.selector
            )
        );
        new ETHRegistrar(
            ethRegistry,
            beneficiary,
            1, // minCommitmentAge
            0, // maxCommitmentAge
            0,
            rentPriceOracle
        );
    }

    function test_setRentPriceOracle() external {
        PaymentRatio[] memory paymentRatios = new PaymentRatio[](1);
        paymentRatios[0] = PaymentRatio(tokenUSDC, 1, 1);
        uint256[] memory baseRates = new uint256[](2);
        baseRates[0] = 1;
        baseRates[1] = 0;
        StandardRentPriceOracle oracle = new StandardRentPriceOracle(
            address(this),
            ethRegistry,
            baseRates,
            0, // \
            0, //  disabled premium
            0, // /
            paymentRatios
        );
        ethRegistrar.setRentPriceOracle(oracle);
        assertTrue(ethRegistrar.isValid("a"), "a");
        assertFalse(ethRegistrar.isValid("ab"), "ab");
        assertFalse(ethRegistrar.isValid("abcdef"), "abcdef");
        assertFalse(ethRegistrar.isPaymentToken(tokenDAI), "DAI");
        (uint256 base, ) = ethRegistrar.rentPrice(
            "a",
            address(0),
            1,
            tokenUSDC
        );
        assertEq(base, 1, "rent"); // 1 * 10^x / 10^x = 1
    }

    function test_Revert_setRentPriceOracle() external {
        PaymentRatio[] memory paymentRatios = new PaymentRatio[](1);
        paymentRatios[0] = PaymentRatio(tokenUSDC, 1, 1);
        StandardRentPriceOracle oracle = new StandardRentPriceOracle(
            address(this),
            ethRegistry,
            new uint256[](0),
            0,
            0,
            0,
            paymentRatios
        );
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                uint256(0),
                ROLE_SET_ORACLE,
                user
            )
        );
        ethRegistrar.setRentPriceOracle(oracle);
        vm.stopPrank();
    }

    function test_isPaymentToken() external view {
        assertTrue(rentPriceOracle.isPaymentToken(tokenUSDC), "USDC");
        assertTrue(rentPriceOracle.isPaymentToken(tokenDAI), "DAI");
        assertTrue(rentPriceOracle.isPaymentToken(tokenBlack), "Black");
        assertFalse(rentPriceOracle.isPaymentToken(IERC20(address(0))));
    }

    // same as StandardRentPriceOracle.t.sol
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

    struct RegisterArgs {
        address sender;
        string label;
        address owner;
        bytes32 secret;
        IRegistry subregistry;
        address resolver;
        uint64 duration;
        IERC20 paymentToken;
        bytes32 referrer;
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
        args.duration = ethRegistrar.minRegisterDuration();
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
                args.duration,
                args.referrer
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
            args.referrer
        );
        vm.stopPrank();
    }

    function _renew(RegisterArgs memory args) external {
        vm.prank(args.sender);
        ethRegistrar.renew(
            args.label,
            args.duration,
            args.paymentToken,
            args.referrer
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
                    args.duration,
                    args.referrer
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

    function test_commitmentAt() external {
        bytes32 commitment = bytes32(uint256(1));
        assertEq(ethRegistrar.commitmentAt(commitment), 0, "before");
        ethRegistrar.commit(commitment);
        assertEq(
            ethRegistrar.commitmentAt(commitment),
            block.timestamp,
            "after"
        );
    function test_Revert_nameNotAvailable() public {
        string memory name = "testname";
        address owner = address(this);
        address resolver = address(0);
        uint64 duration = REGISTRATION_DURATION;
        bytes32 secret = SECRET;
        
        // Register the name first
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            secret, 
            address(registry),
            resolver,
            duration
        );
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        registrar.register(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration,
            address(usdc)
        );
        
        // Try to register again with user1
        vm.startPrank(user1);
        bytes32 secret2 = bytes32(uint256(2345678901));
        
        // Make a commitment
        bytes32 commitment2 = registrar.makeCommitment(
            name, 
            user1, 
            secret2, 
            address(registry),
            resolver,
            duration
        );
        registrar.commit(commitment2);
        
        // Wait for min commitment age to ensure the commitment is valid
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        // Expect registration to fail due to name being unavailable
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.NameNotAvailable.selector, name));
        registrar.register(
            name, 
            user1, 
            secret2,
            registry,
            resolver,
            duration,
            address(usdc)
        );
        vm.stopPrank();
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
        uint256 tokenId = this._register(args);
        uint64 expiry = ethRegistry.getExpiry(tokenId);
        vm.warp(expiry);
        assertEq(
            rentPriceOracle.premiumPrice(expiry),
            rentPriceOracle.premiumPriceAfter(0)
        );
    }

    function test_register_premium_end() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        uint256 tokenId = this._register(args);
        uint64 expiry = ethRegistry.getExpiry(tokenId);
        vm.warp(expiry + rentPriceOracle.premiumPeriod());
        assertEq(rentPriceOracle.premiumPrice(expiry), 0);
    }

    function test_register_premium_latestOwner() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        this._register(args);
        vm.warp(block.timestamp + args.duration);
        (uint256 base, uint256 premium) = ethRegistrar.rentPrice(
            args.label,
            args.owner,
            args.duration,
            args.paymentToken
        );
        assertEq(premium, 0, "premium");
        uint256 balance0 = args.paymentToken.balanceOf(args.owner);
        this._register(args);
        assertEq(
            balance0 - base,
            args.paymentToken.balanceOf(args.owner),
            "balance"
        );
    }

    function test_Revert_register_insufficientAllowance() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        vm.prank(args.sender);
        tokenUSDC.approve(address(ethRegistrar), 0);
        (uint256 base, uint256 premium) = ethRegistrar.rentPrice(
            args.label,
            args.owner,
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
            args.owner,
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
        
        // Verify no ETH charge when using token payment
        assertEq(address(this).balance, initialBalance);
    }

    function test_Revert_register_durationTooShort() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        args.duration = ethRegistrar.minRegisterDuration() - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IETHRegistrar.DurationTooShort.selector,
                args.duration,
                ethRegistrar.minRegisterDuration()
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
            args.owner,
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
    function test_token_payment_renew_no_refund() public {
        string memory name = "testname";
        address owner = address(this);
        address resolver = address(0);
        uint64 duration = REGISTRATION_DURATION;
        bytes32 secret = SECRET;
        
        // Register the name first
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            secret, 
            address(registry),
            resolver,
            duration
        );
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        registrar.register(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration,
            address(usdc)
        );
        
        // Get initial balance
        uint256 initialBalance = address(this).balance;
        
        // Renew with exact payment (tokens don't have excess payment)
        uint64 renewalDuration = 180 days;
        
        registrar.renew(name, renewalDuration, address(usdc));
        
        // Verify no ETH charge when using token payment
        assertEq(address(this).balance, initialBalance);
    }

    function test_supportsInterface() external view {
        assertTrue(
            ERC165Checker.supportsInterface(
                address(ethRegistrar),
                type(IETHRegistrar).interfaceId
            ),
            "IETHRegistrar"
        );
        assertTrue(
            ERC165Checker.supportsInterface(
                address(ethRegistrar),
                type(IRentPriceOracle).interfaceId
            ),
            "IRentPriceOracle"
        );
        console.logBytes4(type(IETHRegistrar).interfaceId);
        console.logBytes4(type(IRentPriceOracle).interfaceId);
    }

    function test_beneficiary_set() external view {
        assertEq(ethRegistrar.beneficiary(), beneficiary);
    function test_registration_default_role_bitmap() public {
        bytes32 commitment = registrar.makeCommitment(
            "testname", 
            user1, 
            SECRET, 
            address(registry),
            address(0),
            REGISTRATION_DURATION
        );
        registrar.commit(commitment);
        
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        uint256 tokenId = registrar.register(
            "testname", 
            user1, 
            SECRET,
            registry,
            address(0),
            REGISTRATION_DURATION,
            address(usdc)
        );

        uint256 resource = registry.testGetResourceFromTokenId(tokenId);

        // Check individual roles using LibRegistryRoles constants

        assertTrue(registry.hasRoles(resource, LibRegistryRoles.ROLE_SET_SUBREGISTRY, user1));
        assertTrue(registry.hasRoles(resource, LibRegistryRoles.ROLE_SET_SUBREGISTRY_ADMIN, user1));
        assertTrue(registry.hasRoles(resource, LibRegistryRoles.ROLE_SET_RESOLVER, user1));
        assertTrue(registry.hasRoles(resource, LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN, user1));
        assertTrue(registry.hasRoles(resource, LibRegistryRoles.ROLE_CAN_TRANSFER, user1));

        // Check combined bitmap
        uint256 ROLE_BITMAP_REGISTRATION = LibRegistryRoles.ROLE_SET_SUBREGISTRY | LibRegistryRoles.ROLE_SET_SUBREGISTRY_ADMIN | LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN | LibRegistryRoles.ROLE_CAN_TRANSFER;
        assertTrue(registry.hasRoles(resource, ROLE_BITMAP_REGISTRATION, user1));
    }

    function test_register_grants_role_can_transfer() public {
        string memory name = "transferable";
        address owner = user2;
        
        bytes32 commitment = registrar.makeCommitment(
            name,
            owner,
            SECRET,
            address(registry),
            address(0),
            REGISTRATION_DURATION
        );
        registrar.commit(commitment);
        
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        uint256 tokenId = registrar.register(
            name,
            owner,
            SECRET,
            registry,
            address(0),
            REGISTRATION_DURATION,
            address(usdc)
        );

        uint256 resource = registry.testGetResourceFromTokenId(tokenId);
        
        // Verify ROLE_CAN_TRANSFER is specifically granted
        assertTrue(registry.hasRoles(resource, LibRegistryRoles.ROLE_CAN_TRANSFER, owner));
        
        // Verify no admin role exists for ROLE_CAN_TRANSFER (as expected per LibRegistryRoles.sol)
        uint256 ROLE_CAN_TRANSFER_ADMIN = LibRegistryRoles.ROLE_CAN_TRANSFER << 128;
        assertFalse(registry.hasRoles(resource, ROLE_CAN_TRANSFER_ADMIN, owner));
    }

    function test_beneficiary_register() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        (uint256 base, ) = ethRegistrar.rentPrice(
            args.label,
            args.owner,
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
            args.owner,
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
}
