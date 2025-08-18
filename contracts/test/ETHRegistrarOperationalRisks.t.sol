// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {MockERC20} from "../src/mocks/MockERC20.sol";
import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {SimpleRegistryMetadata} from "../src/common/SimpleRegistryMetadata.sol";
import {ETHRegistrar, IRegistry} from "../src/L2/ETHRegistrar.sol";
import {PermissionedRegistry} from "../src/common/PermissionedRegistry.sol";
import {LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";

contract MockBlacklist is MockERC20 {
    error Blacklisted(address);
    mapping(address => bool) public isBlacklisted;
    constructor() MockERC20("USDC", "USDC", 6) {}
    function setBlacklisted(address account, bool blacklisted) external {
        isBlacklisted[account] = blacklisted;
    }
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        if (isBlacklisted[from]) revert Blacklisted(from);
        if (isBlacklisted[to]) revert Blacklisted(to);
        return super.transferFrom(from, to, amount);
    }
}

contract MockVoidReturn is MockERC20 {
    constructor() MockERC20("USDT", "USDT", 6) {}
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        super.transferFrom(from, to, amount);
        assembly {
            return(0, 0) // return void
        }
    }
}

contract MockFalseReturn is MockERC20 {
    bool public shouldFail;
    constructor() MockERC20("False Return Token", "FALSE", 18) {}
    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        return false; // return false instead of revert
    }
}

/// @notice Tests for real-world operational risks when using trusted tokens (USDC, USDT, DAI)
///         These tests focus on practical issues that could affect production deployment.
contract TestETHRegistrarOperationalRisks is Test {
    RegistryDatastore datastore;
    PermissionedRegistry ethRegistry;
    ETHRegistrar ethRegistrar;

    MockERC20 tokenOkay;
    MockBlacklist tokenBlack;
    MockVoidReturn tokenVoid;
    MockFalseReturn tokenFalse;

    address user = makeAddr("user");
    address beneficiary = makeAddr("beneficiary");

    function setUp() public {
        vm.warp(2_000_000_000); // avoid timestamp issues

        datastore = new RegistryDatastore();

        ethRegistry = new PermissionedRegistry(
            datastore,
            new SimpleRegistryMetadata(),
            address(this),
            LibEACBaseRoles.ALL_ROLES
        );

        IERC20Metadata[] memory paymentTokens = new IERC20Metadata[](4);
        paymentTokens[0] = tokenOkay = new MockERC20("USD", "USD", 6);
        paymentTokens[1] = tokenBlack = new MockBlacklist();
        paymentTokens[2] = tokenVoid = new MockVoidReturn();
        paymentTokens[3] = tokenFalse = new MockFalseReturn();

        ETHRegistrar.ConstructorArgs memory args;
        args.ethRegistry = ethRegistry;
        args.beneficiary = makeAddr("beneficiary");
        args.maxCommitmentAge = 1;
        args.minRegistrationDuration = 1;
        args.paymentTokens = paymentTokens;
        ethRegistrar = new ETHRegistrar(args);

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
        args.paymentToken = tokenOkay;
        args.duration = ethRegistrar.minRegistrationDuration();
        args.wait = ethRegistrar.minCommitmentAge();
    }

    function _register(
        RegisterArgs memory args
    ) external returns (uint256 tokenId) {
        bytes32 commitment = ethRegistrar.makeCommitment(
            args.label,
            args.owner,
            args.secret,
            args.subregistry,
            args.resolver,
            args.duration
        );
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

    function test_blacklist_user() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        tokenBlack.setBlacklisted(user, true);
        vm.expectRevert(
            abi.encodeWithSelector(MockBlacklist.Blacklisted.selector, user)
        );
        args.paymentToken = tokenBlack;
        this._register(args);
        args.paymentToken = tokenOkay;
        this._register(args);
    }

    function test_blacklist_beneficiary() external {
        RegisterArgs memory args = _defaultRegisterArgs();
        tokenBlack.setBlacklisted(ethRegistrar.beneficiary(), true);
        vm.expectRevert(
            abi.encodeWithSelector(
                MockBlacklist.Blacklisted.selector,
                ethRegistrar.beneficiary()
            )
        );
        args.paymentToken = tokenBlack;
        this._register(args);
        args.paymentToken = tokenOkay;
        this._register(args);
    }

    function test_noReturn_allowed_with_SafeERC20() public {
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
