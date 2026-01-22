// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test, Vm} from "forge-std/Test.sol";

import {
    INameWrapper,
    CANNOT_UNWRAP,
    CANNOT_BURN_FUSES,
    CANNOT_TRANSFER,
    CANNOT_SET_RESOLVER,
    CANNOT_SET_TTL,
    CANNOT_CREATE_SUBDOMAIN,
    IS_DOT_ETH,
    CAN_EXTEND_EXPIRY,
    PARENT_CANNOT_CONTROL
} from "@ens/contracts/wrapper/INameWrapper.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";

import {RegistryRolesLib} from "~src/registry/libraries/RegistryRolesLib.sol";
import {LockedNamesLib} from "~src/migration/libraries/LockedNamesLib.sol";

contract MockNameWrapper {
    mapping(uint256 tokenId => uint32 fuses) public fuses;
    mapping(uint256 tokenId => uint64 expiry) public expiries;
    mapping(uint256 tokenId => address owner) public owners;
    mapping(uint256 tokenId => address resolver) public resolvers;

    event SetResolver(bytes32 indexed node, address resolver);
    event SetFuses(bytes32 indexed node, uint16 fusesToBurn);

    function setFuseData(uint256 tokenId, uint32 _fuses, uint64 _expiry) external {
        fuses[tokenId] = _fuses;
        expiries[tokenId] = _expiry;
    }

    function setInitialResolver(uint256 tokenId, address resolver) external {
        resolvers[tokenId] = resolver;
    }

    function getData(uint256 id) external view returns (address, uint32, uint64) {
        return (owners[id], fuses[id], expiries[id]);
    }

    function setFuses(bytes32 node, uint16 fusesToBurn) external returns (uint32) {
        uint256 tokenId = uint256(node);
        fuses[tokenId] = fuses[tokenId] | fusesToBurn;
        emit SetFuses(node, fusesToBurn);
        return fuses[tokenId];
    }

    function setResolver(bytes32 node, address resolver) external {
        uint256 tokenId = uint256(node);
        resolvers[tokenId] = resolver;
        emit SetResolver(node, resolver);
    }

    function getResolver(uint256 tokenId) external view returns (address) {
        return resolvers[tokenId];
    }
}

contract LibLockedNamesWrapper {
    function validateLockedName(uint32 fuses, uint256 tokenId) external pure {
        LockedNamesLib.validateLockedName(fuses, tokenId);
    }

    function validateEmancipatedName(uint32 fuses, uint256 tokenId) external pure {
        LockedNamesLib.validateEmancipatedName(fuses, tokenId);
    }

    function validateIsDotEth2LD(uint32 fuses, uint256 tokenId) external pure {
        LockedNamesLib.validateIsDotEth2LD(fuses, tokenId);
    }
}

contract LockedNamesLibTest is Test {
    MockNameWrapper nameWrapper;
    VerifiableFactory factory;
    LibLockedNamesWrapper wrapper;

    uint256 testTokenId = 0x1234567890abcdef;

    function setUp() public {
        nameWrapper = new MockNameWrapper();
        factory = new VerifiableFactory();
        wrapper = new LibLockedNamesWrapper();
    }

    function test_freezeName_clears_resolver_when_fuse_not_set() public {
        // Setup name with CANNOT_SET_RESOLVER fuse NOT set
        uint32 initialFuses = CANNOT_UNWRAP | IS_DOT_ETH;
        nameWrapper.setFuseData(testTokenId, initialFuses, uint64(block.timestamp + 86400));

        // Set an initial resolver
        address initialResolver = address(0x9999);
        nameWrapper.setInitialResolver(testTokenId, initialResolver);

        // Verify resolver is initially set
        assertEq(
            nameWrapper.getResolver(testTokenId),
            initialResolver,
            "Initial resolver should be set"
        );

        // Record logs to verify both events are emitted
        vm.recordLogs();

        // Call freezeName
        LockedNamesLib.freezeName(INameWrapper(address(nameWrapper)), testTokenId, initialFuses);

        // Get recorded logs and verify both events were emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2, "Should emit exactly 2 events");

        // Verify setResolver event
        assertEq(
            logs[0].topics[0],
            keccak256("SetResolver(bytes32,address)"),
            "First event should be SetResolver"
        );
        assertEq(
            logs[0].topics[1],
            bytes32(testTokenId),
            "SetResolver event should have correct tokenId"
        );
        address resolverFromEvent = abi.decode(logs[0].data, (address));
        assertEq(
            resolverFromEvent,
            address(0),
            "SetResolver event should set resolver to address(0)"
        );

        // Verify setFuses event
        assertEq(
            logs[1].topics[0],
            keccak256("SetFuses(bytes32,uint16)"),
            "Second event should be SetFuses"
        );
        assertEq(
            logs[1].topics[1],
            bytes32(testTokenId),
            "SetFuses event should have correct tokenId"
        );
        uint16 fusesFromEvent = abi.decode(logs[1].data, (uint16));
        assertEq(
            fusesFromEvent,
            uint16(LockedNamesLib.FUSES_TO_BURN),
            "SetFuses event should burn correct fuses"
        );

        // Verify resolver was cleared
        assertEq(
            nameWrapper.getResolver(testTokenId),
            address(0),
            "Resolver should be cleared to address(0)"
        );

        // Verify all fuses were burned
        (, uint32 finalFuses, ) = nameWrapper.getData(testTokenId);
        assertTrue(
            (finalFuses & LockedNamesLib.FUSES_TO_BURN) == LockedNamesLib.FUSES_TO_BURN,
            "All fuses should be burned"
        );
    }

    function test_freezeName_preserves_resolver_when_fuse_already_set() public {
        // Setup name with CANNOT_SET_RESOLVER fuse already set
        uint32 initialFuses = CANNOT_UNWRAP | IS_DOT_ETH | CANNOT_SET_RESOLVER;
        nameWrapper.setFuseData(testTokenId, initialFuses, uint64(block.timestamp + 86400));

        // Set an initial resolver
        address initialResolver = address(0x8888);
        nameWrapper.setInitialResolver(testTokenId, initialResolver);

        // Verify resolver is initially set
        assertEq(
            nameWrapper.getResolver(testTokenId),
            initialResolver,
            "Initial resolver should be set"
        );

        // Record logs to verify only setFuses event is emitted
        vm.recordLogs();

        // Call freezeName
        LockedNamesLib.freezeName(INameWrapper(address(nameWrapper)), testTokenId, initialFuses);

        // Get recorded logs and verify only setFuses event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "Should emit exactly 1 event (setFuses only)");

        // Verify setFuses event
        assertEq(
            logs[0].topics[0],
            keccak256("SetFuses(bytes32,uint16)"),
            "Event should be SetFuses"
        );
        assertEq(
            logs[0].topics[1],
            bytes32(testTokenId),
            "SetFuses event should have correct tokenId"
        );
        uint16 fusesFromEvent = abi.decode(logs[0].data, (uint16));
        assertEq(
            fusesFromEvent,
            uint16(LockedNamesLib.FUSES_TO_BURN),
            "SetFuses event should burn correct fuses"
        );

        // Verify resolver remains unchanged
        assertEq(
            nameWrapper.getResolver(testTokenId),
            initialResolver,
            "Resolver should be preserved when fuse already set"
        );

        // Verify all fuses were burned
        (, uint32 finalFuses, ) = nameWrapper.getData(testTokenId);
        assertTrue(
            (finalFuses & LockedNamesLib.FUSES_TO_BURN) == LockedNamesLib.FUSES_TO_BURN,
            "All fuses should be burned"
        );
    }

    function test_freezeName_with_zero_resolver_when_fuse_not_set() public {
        // Setup name with CANNOT_SET_RESOLVER fuse NOT set
        uint32 initialFuses = CANNOT_UNWRAP | IS_DOT_ETH;
        nameWrapper.setFuseData(testTokenId, initialFuses, uint64(block.timestamp + 86400));

        // Initial resolver is already address(0) (default)
        assertEq(
            nameWrapper.getResolver(testTokenId),
            address(0),
            "Initial resolver should be address(0)"
        );

        // Record logs to verify both events are emitted
        vm.recordLogs();

        // Call freezeName
        LockedNamesLib.freezeName(INameWrapper(address(nameWrapper)), testTokenId, initialFuses);

        // Get recorded logs and verify both events were emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2, "Should emit exactly 2 events");

        // Verify setResolver event (should still be called even if resolver is already address(0))
        assertEq(
            logs[0].topics[0],
            keccak256("SetResolver(bytes32,address)"),
            "First event should be SetResolver"
        );
        assertEq(
            logs[0].topics[1],
            bytes32(testTokenId),
            "SetResolver event should have correct tokenId"
        );
        address resolverFromEvent = abi.decode(logs[0].data, (address));
        assertEq(
            resolverFromEvent,
            address(0),
            "SetResolver event should set resolver to address(0)"
        );

        // Verify setFuses event
        assertEq(
            logs[1].topics[0],
            keccak256("SetFuses(bytes32,uint16)"),
            "Second event should be SetFuses"
        );
        assertEq(
            logs[1].topics[1],
            bytes32(testTokenId),
            "SetFuses event should have correct tokenId"
        );
        uint16 fusesFromEvent = abi.decode(logs[1].data, (uint16));
        assertEq(
            fusesFromEvent,
            uint16(LockedNamesLib.FUSES_TO_BURN),
            "SetFuses event should burn correct fuses"
        );

        // Verify resolver remains address(0)
        assertEq(
            nameWrapper.getResolver(testTokenId),
            address(0),
            "Resolver should remain address(0)"
        );
    }

    function test_validateLockedName_valid() public pure {
        uint32 validFuses = CANNOT_UNWRAP | IS_DOT_ETH;
        uint256 tokenId = 0x123;

        // Should not revert for valid locked name
        LockedNamesLib.validateLockedName(validFuses, tokenId);
    }

    function test_validateLockedName_with_cannot_burn_fuses() public pure {
        uint32 validFuses = CANNOT_UNWRAP | CANNOT_BURN_FUSES | IS_DOT_ETH;
        uint256 tokenId = 0x123;

        // Should not revert for locked name with CANNOT_BURN_FUSES (previously this would have failed)
        LockedNamesLib.validateLockedName(validFuses, tokenId);
    }

    function test_Revert_validateLockedName_not_locked() public {
        uint32 invalidFuses = IS_DOT_ETH; // Missing CANNOT_UNWRAP
        uint256 tokenId = 0x123;

        vm.expectRevert(abi.encodeWithSelector(LockedNamesLib.NameNotLocked.selector, tokenId));
        wrapper.validateLockedName(invalidFuses, tokenId);
    }

    function test_validateIsDotEth2LD_valid() public pure {
        uint32 validFuses = IS_DOT_ETH | CANNOT_UNWRAP;
        uint256 tokenId = 0x123;

        // Should not revert for valid .eth 2LD
        LockedNamesLib.validateIsDotEth2LD(validFuses, tokenId);
    }

    function test_Revert_validateIsDotEth2LD_not_dot_eth() public {
        uint32 invalidFuses = CANNOT_UNWRAP; // Missing IS_DOT_ETH
        uint256 tokenId = 0x123;

        vm.expectRevert(abi.encodeWithSelector(LockedNamesLib.NotDotEthName.selector, tokenId));
        wrapper.validateIsDotEth2LD(invalidFuses, tokenId);
    }

    function test_generateRoleBitmapsFromFuses_all_permissions() public pure {
        // Fuses that allow all permissions
        uint32 fuses = CANNOT_UNWRAP | IS_DOT_ETH | CAN_EXTEND_EXPIRY;

        (uint256 tokenRoles, uint256 subRegistryRoles) = LockedNamesLib
            .generateRoleBitmapsFromFuses(fuses);

        // Should include renewal and resolver roles since no restrictive fuses are set
        assertTrue((tokenRoles & RegistryRolesLib.ROLE_RENEW) != 0, "Token should have ROLE_RENEW");
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) != 0,
            "Token should have ROLE_RENEW_ADMIN"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER) != 0,
            "Token should have ROLE_SET_RESOLVER"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN) != 0,
            "Token should have ROLE_SET_RESOLVER_ADMIN"
        );
        // Should include transfer role since CANNOT_TRANSFER is not set
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN) != 0,
            "Token should have ROLE_CAN_TRANSFER"
        );
        // Token should NEVER have registrar roles
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_REGISTRAR) == 0,
            "Token should NEVER have ROLE_REGISTRAR"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) == 0,
            "Token should NEVER have ROLE_REGISTRAR_ADMIN"
        );

        // SubRegistry should have registrar roles since subdomain creation is allowed
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR) != 0,
            "SubRegistry should have ROLE_REGISTRAR"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) != 0,
            "SubRegistry should have ROLE_REGISTRAR_ADMIN"
        );
        // SubRegistry should have renewal roles (always granted)
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW) != 0,
            "SubRegistry should have ROLE_RENEW"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) != 0,
            "SubRegistry should have ROLE_RENEW_ADMIN"
        );
    }

    function test_generateRoleBitmapsFromFuses_no_extend_expiry() public pure {
        // Fuses without CAN_EXTEND_EXPIRY
        uint32 fuses = CANNOT_UNWRAP | IS_DOT_ETH;

        (uint256 tokenRoles, uint256 subRegistryRoles) = LockedNamesLib
            .generateRoleBitmapsFromFuses(fuses);

        // Should NOT have renewal roles since CAN_EXTEND_EXPIRY is not set
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_RENEW) == 0,
            "Token should NOT have ROLE_RENEW"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) == 0,
            "Token should NOT have ROLE_RENEW_ADMIN"
        );
        // Should have resolver roles
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER) != 0,
            "Token should have ROLE_SET_RESOLVER"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN) != 0,
            "Token should have ROLE_SET_RESOLVER_ADMIN"
        );
        // Should have transfer role since CANNOT_TRANSFER is not set
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN) != 0,
            "Token should have ROLE_CAN_TRANSFER"
        );
        // Token should NEVER have registrar roles
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_REGISTRAR) == 0,
            "Token should NEVER have ROLE_REGISTRAR"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) == 0,
            "Token should NEVER have ROLE_REGISTRAR_ADMIN"
        );

        // SubRegistry should have registrar roles since subdomain creation is allowed
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR) != 0,
            "SubRegistry should have ROLE_REGISTRAR"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) != 0,
            "SubRegistry should have ROLE_REGISTRAR_ADMIN"
        );
        // SubRegistry should have renewal roles (always granted)
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW) != 0,
            "SubRegistry should have ROLE_RENEW"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) != 0,
            "SubRegistry should have ROLE_RENEW_ADMIN"
        );
    }

    function test_generateRoleBitmapsFromFuses_cannot_set_resolver() public pure {
        // Fuses with CANNOT_SET_RESOLVER
        uint32 fuses = CANNOT_UNWRAP | IS_DOT_ETH | CAN_EXTEND_EXPIRY | CANNOT_SET_RESOLVER;

        (uint256 tokenRoles, uint256 subRegistryRoles) = LockedNamesLib
            .generateRoleBitmapsFromFuses(fuses);

        // Should NOT have resolver roles
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER) == 0,
            "Token should NOT have ROLE_SET_RESOLVER"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN) == 0,
            "Token should NOT have ROLE_SET_RESOLVER_ADMIN"
        );
        // Should have renewal roles
        assertTrue((tokenRoles & RegistryRolesLib.ROLE_RENEW) != 0, "Token should have ROLE_RENEW");
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) != 0,
            "Token should have ROLE_RENEW_ADMIN"
        );
        // Token should NEVER have registrar roles
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_REGISTRAR) == 0,
            "Token should NEVER have ROLE_REGISTRAR"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) == 0,
            "Token should NEVER have ROLE_REGISTRAR_ADMIN"
        );

        // SubRegistry should have registrar roles since subdomain creation is allowed
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR) != 0,
            "SubRegistry should have ROLE_REGISTRAR"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) != 0,
            "SubRegistry should have ROLE_REGISTRAR_ADMIN"
        );
        // SubRegistry should have renewal roles (always granted)
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW) != 0,
            "SubRegistry should have ROLE_RENEW"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) != 0,
            "SubRegistry should have ROLE_RENEW_ADMIN"
        );
    }

    function test_generateRoleBitmapsFromFuses_cannot_create_subdomain() public pure {
        // Fuses with CANNOT_CREATE_SUBDOMAIN
        uint32 fuses = CANNOT_UNWRAP | IS_DOT_ETH | CAN_EXTEND_EXPIRY | CANNOT_CREATE_SUBDOMAIN;

        (uint256 tokenRoles, uint256 subRegistryRoles) = LockedNamesLib
            .generateRoleBitmapsFromFuses(fuses);

        // Token should NOT have registrar roles
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_REGISTRAR) == 0,
            "Token should NOT have ROLE_REGISTRAR"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) == 0,
            "Token should NOT have ROLE_REGISTRAR_ADMIN"
        );
        // Should have renewal and resolver roles
        assertTrue((tokenRoles & RegistryRolesLib.ROLE_RENEW) != 0, "Token should have ROLE_RENEW");
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) != 0,
            "Token should have ROLE_RENEW_ADMIN"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER) != 0,
            "Token should have ROLE_SET_RESOLVER"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN) != 0,
            "Token should have ROLE_SET_RESOLVER_ADMIN"
        );
        // Token should NEVER have registrar roles
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_REGISTRAR) == 0,
            "Token should NEVER have ROLE_REGISTRAR"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) == 0,
            "Token should NEVER have ROLE_REGISTRAR_ADMIN"
        );

        // SubRegistry should NOT have registrar roles since subdomain creation is not allowed
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR) == 0,
            "SubRegistry should NOT have ROLE_REGISTRAR"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) == 0,
            "SubRegistry should NOT have ROLE_REGISTRAR_ADMIN"
        );
        // SubRegistry should have renewal roles (always granted)
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW) != 0,
            "SubRegistry should have ROLE_RENEW"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) != 0,
            "SubRegistry should have ROLE_RENEW_ADMIN"
        );
        // SubRegistry should only have renewal roles when CANNOT_CREATE_SUBDOMAIN is set
        uint256 expectedRoles = RegistryRolesLib.ROLE_RENEW | RegistryRolesLib.ROLE_RENEW_ADMIN;
        assertEq(
            subRegistryRoles,
            expectedRoles,
            "SubRegistry should only have renewal roles when CANNOT_CREATE_SUBDOMAIN is set"
        );
    }

    function test_generateRoleBitmapsFromFuses_cannot_burn_fuses_no_admin_roles() public pure {
        // Fuses with CANNOT_BURN_FUSES - should grant regular roles but NO admin roles
        uint32 fuses = CANNOT_UNWRAP | IS_DOT_ETH | CAN_EXTEND_EXPIRY | CANNOT_BURN_FUSES;

        (uint256 tokenRoles, uint256 subRegistryRoles) = LockedNamesLib
            .generateRoleBitmapsFromFuses(fuses);

        // Should have regular roles but NO admin roles
        assertTrue((tokenRoles & RegistryRolesLib.ROLE_RENEW) != 0, "Token should have ROLE_RENEW");
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) == 0,
            "Token should NOT have ROLE_RENEW_ADMIN when CANNOT_BURN_FUSES is set"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER) != 0,
            "Token should have ROLE_SET_RESOLVER"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN) == 0,
            "Token should NOT have ROLE_SET_RESOLVER_ADMIN when CANNOT_BURN_FUSES is set"
        );

        // SubRegistry should have regular roles but NO admin roles for registrar
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR) != 0,
            "SubRegistry should have ROLE_REGISTRAR"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) == 0,
            "SubRegistry should NOT have ROLE_REGISTRAR_ADMIN when CANNOT_BURN_FUSES is set"
        );
        // SubRegistry should have renewal roles including admin (not affected by CANNOT_BURN_FUSES)
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW) != 0,
            "SubRegistry should have ROLE_RENEW"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) != 0,
            "SubRegistry should have ROLE_RENEW_ADMIN (not affected by CANNOT_BURN_FUSES)"
        );
    }

    function test_generateRoleBitmapsFromFuses_cannot_burn_fuses_with_restrictions() public pure {
        // Fuses with CANNOT_BURN_FUSES + restrictive fuses
        uint32 fuses = CANNOT_UNWRAP |
            IS_DOT_ETH |
            CANNOT_BURN_FUSES |
            CANNOT_SET_RESOLVER |
            CANNOT_CREATE_SUBDOMAIN |
            CANNOT_TRANSFER;
        // Note: no CAN_EXTEND_EXPIRY

        (uint256 tokenRoles, uint256 subRegistryRoles) = LockedNamesLib
            .generateRoleBitmapsFromFuses(fuses);

        // Should NOT have renewal roles (no CAN_EXTEND_EXPIRY)
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_RENEW) == 0,
            "Token should NOT have ROLE_RENEW"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) == 0,
            "Token should NOT have ROLE_RENEW_ADMIN"
        );

        // Should NOT have resolver roles (CANNOT_SET_RESOLVER is set)
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER) == 0,
            "Token should NOT have ROLE_SET_RESOLVER"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN) == 0,
            "Token should NOT have ROLE_SET_RESOLVER_ADMIN"
        );

        // SubRegistry should NOT have registrar roles (CANNOT_CREATE_SUBDOMAIN is set)
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR) == 0,
            "SubRegistry should NOT have ROLE_REGISTRAR"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) == 0,
            "SubRegistry should NOT have ROLE_REGISTRAR_ADMIN"
        );

        // SubRegistry should have renewal roles (always granted)
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW) != 0,
            "SubRegistry should have ROLE_RENEW"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) != 0,
            "SubRegistry should have ROLE_RENEW_ADMIN"
        );

        // Token should have no roles when all permissions are restricted
        assertEq(
            tokenRoles,
            0,
            "Token should have no roles when all permissions are restricted"
        );
        uint256 expectedSubRegistryRoles = RegistryRolesLib.ROLE_RENEW |
            RegistryRolesLib.ROLE_RENEW_ADMIN;
        assertEq(
            subRegistryRoles,
            expectedSubRegistryRoles,
            "SubRegistry should only have renewal roles"
        );
    }

    function test_generateRoleBitmapsFromFuses_cannot_burn_fuses() public pure {
        // Fuses with CANNOT_BURN_FUSES - should prevent admin roles
        uint32 fuses = CANNOT_UNWRAP | IS_DOT_ETH | CAN_EXTEND_EXPIRY | CANNOT_BURN_FUSES;

        (uint256 tokenRoles, uint256 subRegistryRoles) = LockedNamesLib
            .generateRoleBitmapsFromFuses(fuses);

        // Token should have regular roles but NO admin roles due to CANNOT_BURN_FUSES
        assertTrue((tokenRoles & RegistryRolesLib.ROLE_RENEW) != 0, "Token should have ROLE_RENEW");
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) == 0,
            "Token should NOT have ROLE_RENEW_ADMIN when CANNOT_BURN_FUSES is set"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER) != 0,
            "Token should have ROLE_SET_RESOLVER"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN) == 0,
            "Token should NOT have ROLE_SET_RESOLVER_ADMIN when CANNOT_BURN_FUSES is set"
        );

        // SubRegistry should have registrar role but NO admin role due to CANNOT_BURN_FUSES
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR) != 0,
            "SubRegistry should have ROLE_REGISTRAR"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) == 0,
            "SubRegistry should NOT have ROLE_REGISTRAR_ADMIN when CANNOT_BURN_FUSES is set"
        );
        // SubRegistry should have renewal roles (always granted now)
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW) != 0,
            "SubRegistry should have ROLE_RENEW"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) != 0,
            "SubRegistry should have ROLE_RENEW_ADMIN"
        );
    }

    function test_generateRoleBitmapsFromFuses_fuses_control_renewal_roles() public pure {
        // Test that fuses directly control renewal roles via CAN_EXTEND_EXPIRY
        uint32 fusesWithExpiry = CANNOT_UNWRAP | IS_DOT_ETH | CAN_EXTEND_EXPIRY;
        uint32 fusesWithoutExpiry = CANNOT_UNWRAP | IS_DOT_ETH;

        // Test with CAN_EXTEND_EXPIRY set (should have renewal roles)
        (uint256 tokenRoles1, ) = LockedNamesLib.generateRoleBitmapsFromFuses(fusesWithExpiry);
        assertTrue(
            (tokenRoles1 & RegistryRolesLib.ROLE_RENEW) != 0,
            "Should have ROLE_RENEW when CAN_EXTEND_EXPIRY is set"
        );
        assertTrue(
            (tokenRoles1 & RegistryRolesLib.ROLE_RENEW_ADMIN) != 0,
            "Should have ROLE_RENEW_ADMIN when CAN_EXTEND_EXPIRY is set"
        );

        // Test without CAN_EXTEND_EXPIRY (should NOT have renewal roles)
        (uint256 tokenRoles2, ) = LockedNamesLib.generateRoleBitmapsFromFuses(fusesWithoutExpiry);
        assertTrue(
            (tokenRoles2 & RegistryRolesLib.ROLE_RENEW) == 0,
            "Should NOT have ROLE_RENEW without CAN_EXTEND_EXPIRY"
        );
        assertTrue(
            (tokenRoles2 & RegistryRolesLib.ROLE_RENEW_ADMIN) == 0,
            "Should NOT have ROLE_RENEW_ADMIN without CAN_EXTEND_EXPIRY"
        );
    }

    function test_generateRoleBitmapsFromFuses_fuses_consistency() public pure {
        // Test that the same fuses always produce the same roles
        uint32 fuses = CANNOT_UNWRAP | IS_DOT_ETH | CAN_EXTEND_EXPIRY;

        (uint256 tokenRoles1, uint256 subRegistryRoles1) = LockedNamesLib
            .generateRoleBitmapsFromFuses(fuses);
        (uint256 tokenRoles2, uint256 subRegistryRoles2) = LockedNamesLib
            .generateRoleBitmapsFromFuses(fuses);

        // Same fuses should produce identical roles
        assertEq(tokenRoles1, tokenRoles2, "Same fuses should produce identical token roles");
        assertEq(
            subRegistryRoles1,
            subRegistryRoles2,
            "Same fuses should produce identical subregistry roles"
        );

        // Should have all expected roles with this fuse configuration
        assertTrue(
            (tokenRoles1 & RegistryRolesLib.ROLE_SET_RESOLVER) != 0,
            "Should have ROLE_SET_RESOLVER"
        );
        assertTrue(
            (tokenRoles1 & RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN) != 0,
            "Should have ROLE_SET_RESOLVER_ADMIN"
        );
        assertTrue(
            (tokenRoles1 & RegistryRolesLib.ROLE_RENEW) != 0,
            "Should have ROLE_RENEW with CAN_EXTEND_EXPIRY"
        );
        assertTrue(
            (tokenRoles1 & RegistryRolesLib.ROLE_RENEW_ADMIN) != 0,
            "Should have ROLE_RENEW_ADMIN with CAN_EXTEND_EXPIRY"
        );
    }

    function test_generateRoleBitmapsFromFuses_frozen_fuses_behavior() public pure {
        // Test behavior with CANNOT_BURN_FUSES set (fuses are permanently frozen)
        uint32 frozenFuses = CANNOT_UNWRAP | IS_DOT_ETH | CAN_EXTEND_EXPIRY | CANNOT_BURN_FUSES;

        (uint256 tokenRoles, ) = LockedNamesLib.generateRoleBitmapsFromFuses(frozenFuses);

        // Should have ROLE_RENEW since CAN_EXTEND_EXPIRY is set
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_RENEW) != 0,
            "Should have ROLE_RENEW with CAN_EXTEND_EXPIRY"
        );
        // Should NOT have ROLE_RENEW_ADMIN because CANNOT_BURN_FUSES is set (fuses are frozen)
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) == 0,
            "Should NOT have ROLE_RENEW_ADMIN when CANNOT_BURN_FUSES is set"
        );
    }

    function test_generateRoleBitmapsFromFuses_without_can_extend_expiry() public pure {
        // Test that no renewal roles are granted when CAN_EXTEND_EXPIRY is not set
        uint32 fusesWithoutExpiry = CANNOT_UNWRAP | IS_DOT_ETH;

        (uint256 tokenRoles, ) = LockedNamesLib.generateRoleBitmapsFromFuses(fusesWithoutExpiry);

        // Should NOT have renewal roles when CAN_EXTEND_EXPIRY is not set
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_RENEW) == 0,
            "Should NOT have ROLE_RENEW when CAN_EXTEND_EXPIRY not set"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) == 0,
            "Should NOT have ROLE_RENEW_ADMIN when CAN_EXTEND_EXPIRY not set"
        );
    }

    function test_FUSES_TO_BURN_constant() public pure {
        // Verify the FUSES_TO_BURN constant includes all expected fuses including CANNOT_UNWRAP
        uint32 expectedFuses = CANNOT_UNWRAP |
            CANNOT_BURN_FUSES |
            CANNOT_TRANSFER |
            CANNOT_SET_RESOLVER |
            CANNOT_SET_TTL |
            CANNOT_CREATE_SUBDOMAIN;

        assertEq(
            LockedNamesLib.FUSES_TO_BURN,
            expectedFuses,
            "FUSES_TO_BURN should include all expected fuses including CANNOT_UNWRAP"
        );
    }

    function test_freezeName_burns_cannot_unwrap_when_not_set() public {
        // Setup name with CANNOT_UNWRAP fuse NOT set (emancipated but not locked)
        uint32 initialFuses = PARENT_CANNOT_CONTROL | IS_DOT_ETH;
        nameWrapper.setFuseData(testTokenId, initialFuses, uint64(block.timestamp + 86400));

        // Set an initial resolver
        address initialResolver = address(0x9999);
        nameWrapper.setInitialResolver(testTokenId, initialResolver);

        // Verify CANNOT_UNWRAP is initially not set
        (, uint32 currentFuses, ) = nameWrapper.getData(testTokenId);
        assertTrue(
            (currentFuses & CANNOT_UNWRAP) == 0,
            "CANNOT_UNWRAP should not be set initially"
        );

        // Record logs to verify both setResolver and setFuses events are emitted
        vm.recordLogs();

        // Call freezeName
        LockedNamesLib.freezeName(INameWrapper(address(nameWrapper)), testTokenId, initialFuses);

        // Get recorded logs and verify both events were emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2, "Should emit exactly 2 events");

        // Verify setResolver event
        assertEq(
            logs[0].topics[0],
            keccak256("SetResolver(bytes32,address)"),
            "First event should be SetResolver"
        );
        assertEq(
            logs[0].topics[1],
            bytes32(testTokenId),
            "SetResolver event should have correct tokenId"
        );
        address resolverFromEvent = abi.decode(logs[0].data, (address));
        assertEq(
            resolverFromEvent,
            address(0),
            "SetResolver event should set resolver to address(0)"
        );

        // Verify setFuses event
        assertEq(
            logs[1].topics[0],
            keccak256("SetFuses(bytes32,uint16)"),
            "Second event should be SetFuses"
        );
        assertEq(
            logs[1].topics[1],
            bytes32(testTokenId),
            "SetFuses event should have correct tokenId"
        );
        uint16 fusesFromEvent = abi.decode(logs[1].data, (uint16));
        assertEq(
            fusesFromEvent,
            uint16(LockedNamesLib.FUSES_TO_BURN),
            "SetFuses event should burn all fuses including CANNOT_UNWRAP"
        );

        // Verify resolver was cleared
        assertEq(
            nameWrapper.getResolver(testTokenId),
            address(0),
            "Resolver should be cleared to address(0)"
        );

        // Verify all fuses were burned including CANNOT_UNWRAP
        (, uint32 finalFuses, ) = nameWrapper.getData(testTokenId);
        assertTrue(
            (finalFuses & LockedNamesLib.FUSES_TO_BURN) == LockedNamesLib.FUSES_TO_BURN,
            "All fuses including CANNOT_UNWRAP should be burned"
        );
        assertTrue((finalFuses & CANNOT_UNWRAP) != 0, "CANNOT_UNWRAP should now be set");
    }

    function test_validateEmancipatedName_emancipated_only() public pure {
        uint32 emancipatedFuses = PARENT_CANNOT_CONTROL | IS_DOT_ETH;
        uint256 tokenId = 0x123;

        // Should not revert for emancipated name
        LockedNamesLib.validateEmancipatedName(emancipatedFuses, tokenId);
    }

    function test_validateEmancipatedName_emancipated_and_locked() public pure {
        uint32 lockedFuses = PARENT_CANNOT_CONTROL | CANNOT_UNWRAP | IS_DOT_ETH;
        uint256 tokenId = 0x123;

        // Should not revert for emancipated and locked name
        LockedNamesLib.validateEmancipatedName(lockedFuses, tokenId);
    }

    function test_validateEmancipatedName_with_cannot_burn_fuses() public pure {
        uint32 frozenFuses = PARENT_CANNOT_CONTROL | CANNOT_BURN_FUSES | IS_DOT_ETH;
        uint256 tokenId = 0x123;

        // Should not revert for emancipated name with CANNOT_BURN_FUSES (previously this would have failed)
        LockedNamesLib.validateEmancipatedName(frozenFuses, tokenId);
    }

    function test_validateEmancipatedName_locked_with_cannot_burn_fuses() public pure {
        uint32 frozenLockedFuses = PARENT_CANNOT_CONTROL |
            CANNOT_UNWRAP |
            CANNOT_BURN_FUSES |
            IS_DOT_ETH;
        uint256 tokenId = 0x123;

        // Should not revert for emancipated and locked name with CANNOT_BURN_FUSES (previously this would have failed)
        LockedNamesLib.validateEmancipatedName(frozenLockedFuses, tokenId);
    }

    function test_Revert_validateEmancipatedName_not_emancipated() public {
        uint32 notEmancipatedFuses = IS_DOT_ETH; // Missing PARENT_CANNOT_CONTROL
        uint256 tokenId = 0x123;

        vm.expectRevert(
            abi.encodeWithSelector(LockedNamesLib.NameNotEmancipated.selector, tokenId)
        );
        wrapper.validateEmancipatedName(notEmancipatedFuses, tokenId);
    }

    function test_generateRoleBitmapsFromFuses_cannot_transfer_fuse_set() public pure {
        // Fuses with CANNOT_TRANSFER set (transfers disabled)
        uint32 fuses = CANNOT_UNWRAP | IS_DOT_ETH | CAN_EXTEND_EXPIRY | CANNOT_TRANSFER;

        (uint256 tokenRoles, uint256 subRegistryRoles) = LockedNamesLib
            .generateRoleBitmapsFromFuses(fuses);

        // Should have renewal and resolver roles
        assertTrue((tokenRoles & RegistryRolesLib.ROLE_RENEW) != 0, "Token should have ROLE_RENEW");
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) != 0,
            "Token should have ROLE_RENEW_ADMIN"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER) != 0,
            "Token should have ROLE_SET_RESOLVER"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN) != 0,
            "Token should have ROLE_SET_RESOLVER_ADMIN"
        );
        // Should NOT have transfer role since CANNOT_TRANSFER is set
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN) == 0,
            "Token should NOT have ROLE_CAN_TRANSFER when CANNOT_TRANSFER is set"
        );

        // SubRegistry should have registrar roles
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR) != 0,
            "SubRegistry should have ROLE_REGISTRAR"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) != 0,
            "SubRegistry should have ROLE_REGISTRAR_ADMIN"
        );
        // SubRegistry should have renewal roles
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW) != 0,
            "SubRegistry should have ROLE_RENEW"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) != 0,
            "SubRegistry should have ROLE_RENEW_ADMIN"
        );
    }

    function test_generateRoleBitmapsFromFuses_cannot_transfer_fuse_not_set() public pure {
        // Fuses without CANNOT_TRANSFER (transfers allowed)
        uint32 fuses = CANNOT_UNWRAP | IS_DOT_ETH | CAN_EXTEND_EXPIRY;

        (uint256 tokenRoles, uint256 subRegistryRoles) = LockedNamesLib
            .generateRoleBitmapsFromFuses(fuses);

        // Should have renewal and resolver roles
        assertTrue((tokenRoles & RegistryRolesLib.ROLE_RENEW) != 0, "Token should have ROLE_RENEW");
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) != 0,
            "Token should have ROLE_RENEW_ADMIN"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER) != 0,
            "Token should have ROLE_SET_RESOLVER"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN) != 0,
            "Token should have ROLE_SET_RESOLVER_ADMIN"
        );
        // Should have transfer role since CANNOT_TRANSFER is not set
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN) != 0,
            "Token should have ROLE_CAN_TRANSFER when CANNOT_TRANSFER is not set"
        );

        // SubRegistry should have registrar roles
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR) != 0,
            "SubRegistry should have ROLE_REGISTRAR"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) != 0,
            "SubRegistry should have ROLE_REGISTRAR_ADMIN"
        );
        // SubRegistry should have renewal roles
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW) != 0,
            "SubRegistry should have ROLE_RENEW"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) != 0,
            "SubRegistry should have ROLE_RENEW_ADMIN"
        );
    }

    function test_generateRoleBitmapsFromFuses_cannot_transfer_with_cannot_burn_fuses()
        public
        pure
    {
        // Fuses with both CANNOT_TRANSFER and CANNOT_BURN_FUSES
        uint32 fuses = CANNOT_UNWRAP |
            IS_DOT_ETH |
            CAN_EXTEND_EXPIRY |
            CANNOT_TRANSFER |
            CANNOT_BURN_FUSES;

        (uint256 tokenRoles, uint256 subRegistryRoles) = LockedNamesLib
            .generateRoleBitmapsFromFuses(fuses);

        // Should have renewal role but NOT admin role due to CANNOT_BURN_FUSES
        assertTrue((tokenRoles & RegistryRolesLib.ROLE_RENEW) != 0, "Token should have ROLE_RENEW");
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) == 0,
            "Token should NOT have ROLE_RENEW_ADMIN when CANNOT_BURN_FUSES is set"
        );
        // Should have resolver role but NOT admin role due to CANNOT_BURN_FUSES
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER) != 0,
            "Token should have ROLE_SET_RESOLVER"
        );
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN) == 0,
            "Token should NOT have ROLE_SET_RESOLVER_ADMIN when CANNOT_BURN_FUSES is set"
        );
        // Should NOT have transfer role since CANNOT_TRANSFER is set
        assertTrue(
            (tokenRoles & RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN) == 0,
            "Token should NOT have ROLE_CAN_TRANSFER when CANNOT_TRANSFER is set"
        );

        // SubRegistry should have registrar role but NOT admin role due to CANNOT_BURN_FUSES
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR) != 0,
            "SubRegistry should have ROLE_REGISTRAR"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) == 0,
            "SubRegistry should NOT have ROLE_REGISTRAR_ADMIN when CANNOT_BURN_FUSES is set"
        );
        // SubRegistry should have renewal roles (not affected by CANNOT_BURN_FUSES)
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW) != 0,
            "SubRegistry should have ROLE_RENEW"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) != 0,
            "SubRegistry should have ROLE_RENEW_ADMIN"
        );
    }

    function test_generateRoleBitmapsFromFuses_all_restrictive_fuses() public pure {
        // Test with all restrictive fuses including CANNOT_TRANSFER
        uint32 fuses = CANNOT_UNWRAP |
            IS_DOT_ETH |
            CANNOT_TRANSFER |
            CANNOT_SET_RESOLVER |
            CANNOT_CREATE_SUBDOMAIN;
        // Note: no CAN_EXTEND_EXPIRY

        (uint256 tokenRoles, uint256 subRegistryRoles) = LockedNamesLib
            .generateRoleBitmapsFromFuses(fuses);

        // Should have no roles when all restrictive fuses are set
        assertEq(tokenRoles, 0, "Token should have no roles when all restrictive fuses are set");

        // SubRegistry should NOT have registrar roles (CANNOT_CREATE_SUBDOMAIN is set)
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR) == 0,
            "SubRegistry should NOT have ROLE_REGISTRAR"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) == 0,
            "SubRegistry should NOT have ROLE_REGISTRAR_ADMIN"
        );
        // SubRegistry should only have renewal roles
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW) != 0,
            "SubRegistry should have ROLE_RENEW"
        );
        assertTrue(
            (subRegistryRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) != 0,
            "SubRegistry should have ROLE_RENEW_ADMIN"
        );

        // Verify exact role bitmaps
        uint256 expectedSubRegistryRoles = RegistryRolesLib.ROLE_RENEW |
            RegistryRolesLib.ROLE_RENEW_ADMIN;
        assertEq(
            subRegistryRoles,
            expectedSubRegistryRoles,
            "SubRegistry should only have renewal roles with all restrictive fuses"
        );
    }

    function test_generateRoleBitmapsFromFuses_transfer_role_consistency() public pure {
        // Test that transfer role is consistently applied based on CANNOT_TRANSFER fuse

        // Test 1: With CANNOT_TRANSFER - should NOT have transfer role
        uint32 fusesWithCannotTransfer = CANNOT_UNWRAP | IS_DOT_ETH | CANNOT_TRANSFER;
        (uint256 tokenRoles1, ) = LockedNamesLib.generateRoleBitmapsFromFuses(
            fusesWithCannotTransfer
        );
        assertTrue(
            (tokenRoles1 & RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN) == 0,
            "Should NOT have ROLE_CAN_TRANSFER when CANNOT_TRANSFER is set"
        );

        // Test 2: Without CANNOT_TRANSFER - should have transfer role
        uint32 fusesWithoutCannotTransfer = CANNOT_UNWRAP | IS_DOT_ETH;
        (uint256 tokenRoles2, ) = LockedNamesLib.generateRoleBitmapsFromFuses(
            fusesWithoutCannotTransfer
        );
        assertTrue(
            (tokenRoles2 & RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN) != 0,
            "Should have ROLE_CAN_TRANSFER when CANNOT_TRANSFER is not set"
        );

        // Test 3: With other restrictive fuses but not CANNOT_TRANSFER - should have transfer role
        uint32 fusesWithOtherRestrictions = CANNOT_UNWRAP |
            IS_DOT_ETH |
            CANNOT_SET_RESOLVER |
            CANNOT_CREATE_SUBDOMAIN;
        (uint256 tokenRoles3, ) = LockedNamesLib.generateRoleBitmapsFromFuses(
            fusesWithOtherRestrictions
        );
        assertTrue(
            (tokenRoles3 & RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN) != 0,
            "Should have ROLE_CAN_TRANSFER when CANNOT_TRANSFER is not set even with other restrictions"
        );

        // Test 4: With CANNOT_TRANSFER and other restrictive fuses - should NOT have transfer role
        uint32 fusesWithCannotTransferAndOthers = CANNOT_UNWRAP |
            IS_DOT_ETH |
            CANNOT_TRANSFER |
            CANNOT_SET_RESOLVER;
        (uint256 tokenRoles4, ) = LockedNamesLib.generateRoleBitmapsFromFuses(
            fusesWithCannotTransferAndOthers
        );
        assertTrue(
            (tokenRoles4 & RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN) == 0,
            "Should NOT have ROLE_CAN_TRANSFER when CANNOT_TRANSFER is set regardless of other restrictions"
        );
    }
}
