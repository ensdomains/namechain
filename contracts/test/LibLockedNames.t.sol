// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {INameWrapper, CANNOT_UNWRAP, CANNOT_BURN_FUSES, CANNOT_TRANSFER, CANNOT_SET_RESOLVER, CANNOT_SET_TTL, CANNOT_CREATE_SUBDOMAIN, CANNOT_APPROVE, IS_DOT_ETH, CAN_EXTEND_EXPIRY, PARENT_CANNOT_CONTROL} from "@ens/contracts/wrapper/INameWrapper.sol";
import {LibLockedNames} from "../src/L1/LibLockedNames.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";
import {VerifiableFactory} from "../lib/verifiable-factory/src/VerifiableFactory.sol";

contract MockNameWrapper {
    mapping(uint256 => uint32) public fuses;
    mapping(uint256 => uint64) public expiries;
    mapping(uint256 => address) public owners;
    mapping(uint256 => address) public resolvers;
    
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
        LibLockedNames.validateLockedName(fuses, tokenId);
    }
    
    function validateEmancipatedName(uint32 fuses, uint256 tokenId) external pure {
        LibLockedNames.validateEmancipatedName(fuses, tokenId);
    }
    
    function validateIsDotEth2LD(uint32 fuses, uint256 tokenId) external pure {
        LibLockedNames.validateIsDotEth2LD(fuses, tokenId);
    }
}

contract TestLibLockedNames is Test {
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
        assertEq(nameWrapper.getResolver(testTokenId), initialResolver, "Initial resolver should be set");
        
        // Record logs to verify both events are emitted
        vm.recordLogs();
        
        // Call freezeName
        LibLockedNames.freezeName(INameWrapper(address(nameWrapper)), testTokenId, initialFuses);
        
        // Get recorded logs and verify both events were emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2, "Should emit exactly 2 events");
        
        // Verify setResolver event
        assertEq(logs[0].topics[0], keccak256("SetResolver(bytes32,address)"), "First event should be SetResolver");
        assertEq(logs[0].topics[1], bytes32(testTokenId), "SetResolver event should have correct tokenId");
        address resolverFromEvent = abi.decode(logs[0].data, (address));
        assertEq(resolverFromEvent, address(0), "SetResolver event should set resolver to address(0)");
        
        // Verify setFuses event
        assertEq(logs[1].topics[0], keccak256("SetFuses(bytes32,uint16)"), "Second event should be SetFuses");
        assertEq(logs[1].topics[1], bytes32(testTokenId), "SetFuses event should have correct tokenId");
        uint16 fusesFromEvent = abi.decode(logs[1].data, (uint16));
        assertEq(fusesFromEvent, uint16(LibLockedNames.FUSES_TO_BURN), "SetFuses event should burn correct fuses");
        
        // Verify resolver was cleared
        assertEq(nameWrapper.getResolver(testTokenId), address(0), "Resolver should be cleared to address(0)");
        
        // Verify all fuses were burned
        (, uint32 finalFuses, ) = nameWrapper.getData(testTokenId);
        assertTrue((finalFuses & LibLockedNames.FUSES_TO_BURN) == LibLockedNames.FUSES_TO_BURN, "All fuses should be burned");
    }
    
    function test_freezeName_preserves_resolver_when_fuse_already_set() public {
        // Setup name with CANNOT_SET_RESOLVER fuse already set
        uint32 initialFuses = CANNOT_UNWRAP | IS_DOT_ETH | CANNOT_SET_RESOLVER;
        nameWrapper.setFuseData(testTokenId, initialFuses, uint64(block.timestamp + 86400));
        
        // Set an initial resolver
        address initialResolver = address(0x8888);
        nameWrapper.setInitialResolver(testTokenId, initialResolver);
        
        // Verify resolver is initially set
        assertEq(nameWrapper.getResolver(testTokenId), initialResolver, "Initial resolver should be set");
        
        // Record logs to verify only setFuses event is emitted
        vm.recordLogs();
        
        // Call freezeName
        LibLockedNames.freezeName(INameWrapper(address(nameWrapper)), testTokenId, initialFuses);
        
        // Get recorded logs and verify only setFuses event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "Should emit exactly 1 event (setFuses only)");
        
        // Verify setFuses event
        assertEq(logs[0].topics[0], keccak256("SetFuses(bytes32,uint16)"), "Event should be SetFuses");
        assertEq(logs[0].topics[1], bytes32(testTokenId), "SetFuses event should have correct tokenId");
        uint16 fusesFromEvent = abi.decode(logs[0].data, (uint16));
        assertEq(fusesFromEvent, uint16(LibLockedNames.FUSES_TO_BURN), "SetFuses event should burn correct fuses");
        
        // Verify resolver remains unchanged
        assertEq(nameWrapper.getResolver(testTokenId), initialResolver, "Resolver should be preserved when fuse already set");
        
        // Verify all fuses were burned
        (, uint32 finalFuses, ) = nameWrapper.getData(testTokenId);
        assertTrue((finalFuses & LibLockedNames.FUSES_TO_BURN) == LibLockedNames.FUSES_TO_BURN, "All fuses should be burned");
    }
    
    function test_freezeName_with_zero_resolver_when_fuse_not_set() public {
        // Setup name with CANNOT_SET_RESOLVER fuse NOT set
        uint32 initialFuses = CANNOT_UNWRAP | IS_DOT_ETH;
        nameWrapper.setFuseData(testTokenId, initialFuses, uint64(block.timestamp + 86400));
        
        // Initial resolver is already address(0) (default)
        assertEq(nameWrapper.getResolver(testTokenId), address(0), "Initial resolver should be address(0)");
        
        // Record logs to verify both events are emitted
        vm.recordLogs();
        
        // Call freezeName
        LibLockedNames.freezeName(INameWrapper(address(nameWrapper)), testTokenId, initialFuses);
        
        // Get recorded logs and verify both events were emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2, "Should emit exactly 2 events");
        
        // Verify setResolver event (should still be called even if resolver is already address(0))
        assertEq(logs[0].topics[0], keccak256("SetResolver(bytes32,address)"), "First event should be SetResolver");
        assertEq(logs[0].topics[1], bytes32(testTokenId), "SetResolver event should have correct tokenId");
        address resolverFromEvent = abi.decode(logs[0].data, (address));
        assertEq(resolverFromEvent, address(0), "SetResolver event should set resolver to address(0)");
        
        // Verify setFuses event
        assertEq(logs[1].topics[0], keccak256("SetFuses(bytes32,uint16)"), "Second event should be SetFuses");
        assertEq(logs[1].topics[1], bytes32(testTokenId), "SetFuses event should have correct tokenId");
        uint16 fusesFromEvent = abi.decode(logs[1].data, (uint16));
        assertEq(fusesFromEvent, uint16(LibLockedNames.FUSES_TO_BURN), "SetFuses event should burn correct fuses");
        
        // Verify resolver remains address(0)
        assertEq(nameWrapper.getResolver(testTokenId), address(0), "Resolver should remain address(0)");
    }
    
    function test_validateLockedName_valid() public pure {
        uint32 validFuses = CANNOT_UNWRAP | IS_DOT_ETH;
        uint256 tokenId = 0x123;
        
        // Should not revert for valid locked name
        LibLockedNames.validateLockedName(validFuses, tokenId);
    }
    
    function test_Revert_validateLockedName_not_locked() public {
        uint32 invalidFuses = IS_DOT_ETH; // Missing CANNOT_UNWRAP
        uint256 tokenId = 0x123;
        
        vm.expectRevert(abi.encodeWithSelector(LibLockedNames.NameNotLocked.selector, tokenId));
        wrapper.validateLockedName(invalidFuses, tokenId);
    }
    
    function test_Revert_validateLockedName_cannot_be_migrated() public {
        uint32 nonMigratableFuses = CANNOT_UNWRAP | CANNOT_BURN_FUSES | IS_DOT_ETH;
        uint256 tokenId = 0x123;
        
        vm.expectRevert(abi.encodeWithSelector(LibLockedNames.NameCannotBeMigrated.selector, tokenId));
        wrapper.validateLockedName(nonMigratableFuses, tokenId);
    }
    
    function test_validateIsDotEth2LD_valid() public pure {
        uint32 validFuses = IS_DOT_ETH | CANNOT_UNWRAP;
        uint256 tokenId = 0x123;
        
        // Should not revert for valid .eth 2LD
        LibLockedNames.validateIsDotEth2LD(validFuses, tokenId);
    }
    
    function test_Revert_validateIsDotEth2LD_not_dot_eth() public {
        uint32 invalidFuses = CANNOT_UNWRAP; // Missing IS_DOT_ETH
        uint256 tokenId = 0x123;
        
        vm.expectRevert(abi.encodeWithSelector(LibLockedNames.NotDotEthName.selector, tokenId));
        wrapper.validateIsDotEth2LD(invalidFuses, tokenId);
    }
    
    function test_generateRoleBitmapsFromFuses_all_permissions() public pure {
        // Fuses that allow all permissions
        uint32 fuses = CANNOT_UNWRAP | IS_DOT_ETH | CAN_EXTEND_EXPIRY;
        
        (uint256 tokenRoles, uint256 subRegistryRoles) = LibLockedNames.generateRoleBitmapsFromFuses(fuses);
        
        // Should include renewal and resolver roles since no restrictive fuses are set
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_RENEW) != 0, "Token should have ROLE_RENEW");
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_RENEW_ADMIN) != 0, "Token should have ROLE_RENEW_ADMIN");
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_SET_RESOLVER) != 0, "Token should have ROLE_SET_RESOLVER");
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN) != 0, "Token should have ROLE_SET_RESOLVER_ADMIN");
        // Token should NEVER have registrar roles
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_REGISTRAR) == 0, "Token should NEVER have ROLE_REGISTRAR");
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_REGISTRAR_ADMIN) == 0, "Token should NEVER have ROLE_REGISTRAR_ADMIN");
        
        // SubRegistry should have registrar roles since subdomain creation is allowed
        assertTrue((subRegistryRoles & LibRegistryRoles.ROLE_REGISTRAR) != 0, "SubRegistry should have ROLE_REGISTRAR");
        assertTrue((subRegistryRoles & LibRegistryRoles.ROLE_REGISTRAR_ADMIN) != 0, "SubRegistry should have ROLE_REGISTRAR_ADMIN");
    }
    
    function test_generateRoleBitmapsFromFuses_no_extend_expiry() public pure {
        // Fuses without CAN_EXTEND_EXPIRY
        uint32 fuses = CANNOT_UNWRAP | IS_DOT_ETH;
        
        (uint256 tokenRoles, uint256 subRegistryRoles) = LibLockedNames.generateRoleBitmapsFromFuses(fuses);
        
        // Should NOT have renewal roles since CAN_EXTEND_EXPIRY is not set
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_RENEW) == 0, "Token should NOT have ROLE_RENEW");
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_RENEW_ADMIN) == 0, "Token should NOT have ROLE_RENEW_ADMIN");
        // Should have resolver roles
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_SET_RESOLVER) != 0, "Token should have ROLE_SET_RESOLVER");
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN) != 0, "Token should have ROLE_SET_RESOLVER_ADMIN");
        // Token should NEVER have registrar roles
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_REGISTRAR) == 0, "Token should NEVER have ROLE_REGISTRAR");
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_REGISTRAR_ADMIN) == 0, "Token should NEVER have ROLE_REGISTRAR_ADMIN");
        
        // SubRegistry should have registrar roles since subdomain creation is allowed
        assertTrue((subRegistryRoles & LibRegistryRoles.ROLE_REGISTRAR) != 0, "SubRegistry should have ROLE_REGISTRAR");
        assertTrue((subRegistryRoles & LibRegistryRoles.ROLE_REGISTRAR_ADMIN) != 0, "SubRegistry should have ROLE_REGISTRAR_ADMIN");
    }
    
    
    function test_generateRoleBitmapsFromFuses_cannot_set_resolver() public pure {
        // Fuses with CANNOT_SET_RESOLVER
        uint32 fuses = CANNOT_UNWRAP | IS_DOT_ETH | CAN_EXTEND_EXPIRY | CANNOT_SET_RESOLVER;
        
        (uint256 tokenRoles, uint256 subRegistryRoles) = LibLockedNames.generateRoleBitmapsFromFuses(fuses);
        
        // Should NOT have resolver roles
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_SET_RESOLVER) == 0, "Token should NOT have ROLE_SET_RESOLVER");
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN) == 0, "Token should NOT have ROLE_SET_RESOLVER_ADMIN");
        // Should have renewal roles
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_RENEW) != 0, "Token should have ROLE_RENEW");
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_RENEW_ADMIN) != 0, "Token should have ROLE_RENEW_ADMIN");
        // Token should NEVER have registrar roles
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_REGISTRAR) == 0, "Token should NEVER have ROLE_REGISTRAR");
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_REGISTRAR_ADMIN) == 0, "Token should NEVER have ROLE_REGISTRAR_ADMIN");
        
        // SubRegistry should have registrar roles since subdomain creation is allowed
        assertTrue((subRegistryRoles & LibRegistryRoles.ROLE_REGISTRAR) != 0, "SubRegistry should have ROLE_REGISTRAR");
        assertTrue((subRegistryRoles & LibRegistryRoles.ROLE_REGISTRAR_ADMIN) != 0, "SubRegistry should have ROLE_REGISTRAR_ADMIN");
    }
    
    function test_generateRoleBitmapsFromFuses_cannot_create_subdomain() public pure {
        // Fuses with CANNOT_CREATE_SUBDOMAIN
        uint32 fuses = CANNOT_UNWRAP | IS_DOT_ETH | CAN_EXTEND_EXPIRY | CANNOT_CREATE_SUBDOMAIN;
        
        (uint256 tokenRoles, uint256 subRegistryRoles) = LibLockedNames.generateRoleBitmapsFromFuses(fuses);
        
        // Token should NOT have registrar roles
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_REGISTRAR) == 0, "Token should NOT have ROLE_REGISTRAR");
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_REGISTRAR_ADMIN) == 0, "Token should NOT have ROLE_REGISTRAR_ADMIN");
        // Should have renewal and resolver roles
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_RENEW) != 0, "Token should have ROLE_RENEW");
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_RENEW_ADMIN) != 0, "Token should have ROLE_RENEW_ADMIN");
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_SET_RESOLVER) != 0, "Token should have ROLE_SET_RESOLVER");
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN) != 0, "Token should have ROLE_SET_RESOLVER_ADMIN");
        // Token should NEVER have registrar roles
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_REGISTRAR) == 0, "Token should NEVER have ROLE_REGISTRAR");
        assertTrue((tokenRoles & LibRegistryRoles.ROLE_REGISTRAR_ADMIN) == 0, "Token should NEVER have ROLE_REGISTRAR_ADMIN");
        
        // SubRegistry should NOT have registrar roles since subdomain creation is not allowed
        assertTrue((subRegistryRoles & LibRegistryRoles.ROLE_REGISTRAR) == 0, "SubRegistry should NOT have ROLE_REGISTRAR");
        assertTrue((subRegistryRoles & LibRegistryRoles.ROLE_REGISTRAR_ADMIN) == 0, "SubRegistry should NOT have ROLE_REGISTRAR_ADMIN");
        // SubRegistry should be 0 (no roles)
        assertEq(subRegistryRoles, 0, "SubRegistry roles should be 0 when CANNOT_CREATE_SUBDOMAIN is set");
    }
    
    function test_FUSES_TO_BURN_constant() public pure {
        // Verify the FUSES_TO_BURN constant includes all expected fuses including CANNOT_UNWRAP
        uint32 expectedFuses = CANNOT_UNWRAP | CANNOT_BURN_FUSES | CANNOT_TRANSFER | CANNOT_SET_RESOLVER | 
                               CANNOT_SET_TTL | CANNOT_CREATE_SUBDOMAIN | CANNOT_APPROVE;
        
        assertEq(LibLockedNames.FUSES_TO_BURN, expectedFuses, "FUSES_TO_BURN should include all expected fuses including CANNOT_UNWRAP");
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
        assertTrue((currentFuses & CANNOT_UNWRAP) == 0, "CANNOT_UNWRAP should not be set initially");
        
        // Record logs to verify both setResolver and setFuses events are emitted
        vm.recordLogs();
        
        // Call freezeName
        LibLockedNames.freezeName(INameWrapper(address(nameWrapper)), testTokenId, initialFuses);
        
        // Get recorded logs and verify both events were emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2, "Should emit exactly 2 events");
        
        // Verify setResolver event
        assertEq(logs[0].topics[0], keccak256("SetResolver(bytes32,address)"), "First event should be SetResolver");
        assertEq(logs[0].topics[1], bytes32(testTokenId), "SetResolver event should have correct tokenId");
        address resolverFromEvent = abi.decode(logs[0].data, (address));
        assertEq(resolverFromEvent, address(0), "SetResolver event should set resolver to address(0)");
        
        // Verify setFuses event
        assertEq(logs[1].topics[0], keccak256("SetFuses(bytes32,uint16)"), "Second event should be SetFuses");
        assertEq(logs[1].topics[1], bytes32(testTokenId), "SetFuses event should have correct tokenId");
        uint16 fusesFromEvent = abi.decode(logs[1].data, (uint16));
        assertEq(fusesFromEvent, uint16(LibLockedNames.FUSES_TO_BURN), "SetFuses event should burn all fuses including CANNOT_UNWRAP");
        
        // Verify resolver was cleared
        assertEq(nameWrapper.getResolver(testTokenId), address(0), "Resolver should be cleared to address(0)");
        
        // Verify all fuses were burned including CANNOT_UNWRAP
        (, uint32 finalFuses, ) = nameWrapper.getData(testTokenId);
        assertTrue((finalFuses & LibLockedNames.FUSES_TO_BURN) == LibLockedNames.FUSES_TO_BURN, "All fuses including CANNOT_UNWRAP should be burned");
        assertTrue((finalFuses & CANNOT_UNWRAP) != 0, "CANNOT_UNWRAP should now be set");
    }
    
    function test_validateEmancipatedName_emancipated_only() public pure {
        uint32 emancipatedFuses = PARENT_CANNOT_CONTROL | IS_DOT_ETH;
        uint256 tokenId = 0x123;
        
        // Should not revert for emancipated name
        LibLockedNames.validateEmancipatedName(emancipatedFuses, tokenId);
    }
    
    function test_validateEmancipatedName_emancipated_and_locked() public pure {
        uint32 lockedFuses = PARENT_CANNOT_CONTROL | CANNOT_UNWRAP | IS_DOT_ETH;
        uint256 tokenId = 0x123;
        
        // Should not revert for emancipated and locked name
        LibLockedNames.validateEmancipatedName(lockedFuses, tokenId);
    }
    
    
    function test_Revert_validateEmancipatedName_not_emancipated() public {
        uint32 notEmancipatedFuses = IS_DOT_ETH; // Missing PARENT_CANNOT_CONTROL
        uint256 tokenId = 0x123;
        
        vm.expectRevert(abi.encodeWithSelector(LibLockedNames.NameNotEmancipated.selector, tokenId));
        wrapper.validateEmancipatedName(notEmancipatedFuses, tokenId);
    }
    
    
    function test_Revert_validateEmancipatedName_cannot_be_migrated() public {
        uint32 nonMigratableFuses = PARENT_CANNOT_CONTROL | CANNOT_BURN_FUSES | IS_DOT_ETH;
        uint256 tokenId = 0x123;
        
        vm.expectRevert(abi.encodeWithSelector(LibLockedNames.NameCannotBeMigrated.selector, tokenId));
        wrapper.validateEmancipatedName(nonMigratableFuses, tokenId);
    }
}