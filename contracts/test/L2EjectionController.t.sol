// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

import "../src/L2/L2EjectionController.sol";
import "../src/L2/L2ETHRegistry.sol"; // Use the actual L2 registry
import "../src/common/IStandardRegistry.sol";
import "../src/common/IRegistry.sol";
import "../src/common/ITokenObserver.sol";
import "../src/common/RegistryDatastore.sol";
import "../src/common/IRegistryDatastore.sol";
import "../src/common/IRegistryMetadata.sol";
import "../src/common/NameUtils.sol"; // Needed for label hashing
import {RegistryRolesMixin} from "../src/common/RegistryRolesMixin.sol"; // Needed for ALL_ROLES
import {EnhancedAccessControl} from "../src/common/EnhancedAccessControl.sol"; // Needed for ROOT_RESOURCE, ALL_ROLES

contract MockRegistryMetadata is IRegistryMetadata {
    function tokenUri(uint256) external pure override returns (string memory) {
        return "";
    }
}

contract TestL2EjectionController is Test, ERC1155Holder, RegistryRolesMixin {
    // Import constants from RegistryRolesMixin and EnhancedAccessControl
    bytes32 constant ROOT_RESOURCE = bytes32(0);
    uint256 constant ALL_ROLES = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    
    L2EjectionController controller;
    L2ETHRegistry registry;
    RegistryDatastore datastore;
    MockRegistryMetadata registryMetadata;

    address user = address(0x1);
    address l1Owner = address(0x2);
    address l1Subregistry = address(0x3);
    address l1Resolver = address(0x6);
    address l2Owner = address(0x4);
    address l2Subregistry = address(0x5);
    address l2Resolver = address(0x7);
    
    string label = "test";
    uint256 labelHash; // = NameUtils.labelToCanonicalId(label);
    uint256 tokenId; // Will be derived from labelHash and version
    uint64 expiryDuration = 86400; // 1 day

    function setUp() public {
        datastore = new RegistryDatastore();
        registryMetadata = new MockRegistryMetadata();
        // Initially deploy registry with this contract as a temporary controller
        registry = new L2ETHRegistry(datastore, IL2EjectionController(address(this)), registryMetadata);
        // Deploy the actual controller we want to test
        controller = new L2EjectionController(registry);
        // Now set the *real* controller on the registry (requires admin role, which setUp has)
        registry.setEjectionController(controller);
        
        labelHash = NameUtils.labelToCanonicalId(label);
    }

    // Helper to register a name and get its tokenId
    function _registerName(address owner) internal returns (uint256) {
        uint64 expires = uint64(block.timestamp + expiryDuration);
        // Grant this test contract the registrar role
        registry.grantRootRoles(ROLE_REGISTRAR, address(this));
        // Register the name
        uint256 registeredTokenId = registry.register(label, owner, registry, address(0), ALL_ROLES, expires);
        vm.warp(block.timestamp + 1); // Ensure timestamp moves forward if needed for expiry checks
        return registeredTokenId;
    }

    // Helper to eject a name
    function _ejectName(uint256 _tokenId, address _l1Owner, address _l1Subregistry, address _l1Resolver) internal {
        // Eject needs to be called by the token owner
        address owner = registry.ownerOf(_tokenId);
        vm.startPrank(owner);
        registry.eject(_tokenId, _l1Owner, _l1Subregistry, _l1Resolver);
        vm.stopPrank();
    }

    function test_constructor() public view {
        assertEq(address(controller.registry()), address(registry));
    }

    function test_eject_flow_emits_event() public {
        // Setup: Register a name owned by this test contract
        tokenId = _registerName(address(this));
        uint64 initialExpiry = registry.getExpiry(tokenId);
        
        vm.recordLogs();
        _ejectName(tokenId, l1Owner, l1Subregistry, l1Resolver);

        // Verify event emitted by the controller
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundEjected = false;
        for(uint i = 0; i < entries.length; i++) {
            if(entries[i].topics[0] == keccak256("NameEjectedToL1(uint256,address,address,address,uint64)")) {
                assertEq(uint256(entries[i].topics[1]), tokenId, "Event tokenId mismatch");
                (address emittedL1Owner, address emittedL1Subregistry, address emittedL1Resolver, uint64 emittedExpiry) = abi.decode(entries[i].data, (address, address, address, uint64));
                assertEq(emittedL1Owner, l1Owner, "Event l1Owner mismatch");
                assertEq(emittedL1Subregistry, l1Subregistry, "Event l1Subregistry mismatch");
                assertEq(emittedL1Resolver, l1Resolver, "Event l1Resolver mismatch");
                assertEq(emittedExpiry, initialExpiry, "Event expiry mismatch");
                foundEjected = true;
                break;
            }
        }
        assertTrue(foundEjected, "NameEjectedToL1 event not found");

        // Verify subregistry is cleared in the registry after ejection
        (address subregAddr, , ) = datastore.getSubregistry(tokenId);
        assertEq(subregAddr, address(0), "Subregistry not cleared after ejection");
        // Verify token is now owned by the controller
        assertEq(registry.ownerOf(tokenId), address(controller), "Token not owned by controller after ejection");
    }

    // test_Revert_ejectToL1_notOwner becomes implicitly tested by L2ETHRegistry's onlyTokenOwner modifier on eject

    function test_completeMigrationToL2() public {
        // Setup: Register and eject a name. Token is now owned by controller.
        tokenId = _registerName(address(this));
        _ejectName(tokenId, l1Owner, l1Subregistry, l1Resolver);
        assertEq(registry.ownerOf(tokenId), address(controller), "Setup failed: Controller doesn't own token after eject");

        vm.recordLogs();
        // Simulate the cross-chain message calling the controller
        controller.completeMigrationToL2(tokenId, l2Owner, l2Subregistry, l2Resolver);

        // Verify subregistry is set correctly in the registry 
        IRegistry subregAddr = registry.getSubregistry(label);
        assertEq(address(subregAddr), l2Subregistry, "Subregistry not set correctly after migration");

        // Verify resolver is set correctly
        address resolverAddr = registry.getResolver(label);
        assertEq(resolverAddr, l2Resolver, "Resolver not set correctly after migration");

        // Verify token ownership transferred
        assertEq(registry.ownerOf(tokenId), l2Owner, "Token ownership not transferred after migration"); 

        // Verify event emitted by the controller
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundMigrated = false;
        for(uint i = 0; i < entries.length; i++) {
            if(entries[i].topics[0] == keccak256("NameMigratedToL2(uint256,address,address,address)")) {
                assertEq(uint256(entries[i].topics[1]), tokenId, "Event tokenId mismatch");
                 (address emittedL2Owner, address emittedL2Subregistry, address emittedL2Resolver) = abi.decode(entries[i].data, (address, address, address));
                 assertEq(emittedL2Owner, l2Owner, "Event l2Owner mismatch");
                 assertEq(emittedL2Subregistry, l2Subregistry, "Event l2Subregistry mismatch");
                 assertEq(emittedL2Resolver, l2Resolver, "Event l2Resolver mismatch");
                 foundMigrated = true;
                 break;
            }
        }
        assertTrue(foundMigrated, "NameMigratedToL2 event not found");
    }

    function test_Revert_completeMigrationToL2_notOwner() public {
         // Setup: Register a name owned by the test contract, but DO NOT eject it.
         // The controller never owns the token in this case.
        tokenId = _registerName(address(this));
        assertEq(registry.ownerOf(tokenId), address(this), "Setup failed: Test contract should own token");

        // Expect revert with NotTokenOwner error 
        vm.expectRevert(abi.encodeWithSelector(L2EjectionController.NotTokenOwner.selector, tokenId));
        controller.completeMigrationToL2(tokenId, l2Owner, l2Subregistry, l2Resolver);
    }

    function test_supportsInterface() public view {
        assertTrue(controller.supportsInterface(type(IL2EjectionController).interfaceId));
        assertTrue(controller.supportsInterface(type(ITokenObserver).interfaceId));
        assertTrue(controller.supportsInterface(type(IERC1155Receiver).interfaceId));
        assertFalse(controller.supportsInterface(0x12345678));
    }

    function test_onERC1155Received() public view {
        bytes4 selector = controller.onERC1155Received(address(0), address(0), 0, 0, "");
        assertEq(selector, IERC1155Receiver.onERC1155Received.selector);
    }

    function test_onERC1155BatchReceived() public view {
         uint256[] memory ids;
         uint256[] memory values;
         bytes4 selector = controller.onERC1155BatchReceived(address(0), address(0), ids, values, "");
         assertEq(selector, IERC1155Receiver.onERC1155BatchReceived.selector);
    }

    function test_onRenew_emitsEvent_whenOwner() public {
        // Setup: Register and eject. Controller owns the token.
        tokenId = _registerName(address(this));
        _ejectName(tokenId, l1Owner, l1Subregistry, l1Resolver);
        assertEq(registry.ownerOf(tokenId), address(controller), "Setup failed: Controller doesn't own token after eject");

        // Before renewing, confirm that the token still exists and has the right owner
        assertEq(registry.ownerOf(tokenId), address(controller));
        
        vm.recordLogs();
        uint64 newExpiry = uint64(block.timestamp + expiryDuration * 2);
        registry.renew(tokenId, newExpiry);

        // Check for the NameRenewed event emitted by the controller's onRenew hook
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundRenewed = false;
        
        for(uint i = 0; i < entries.length; i++) {
            bytes32 topic0 = entries[i].topics[0];
            address emitter = entries[i].emitter;
            
            if(topic0 == keccak256("NameRenewed(uint256,uint64,address)") && emitter == address(controller)) {
                assertEq(uint256(entries[i].topics[1]), tokenId, "Renew Event tokenId mismatch");
                (uint64 emittedExpiry, address emittedRenewer) = abi.decode(entries[i].data, (uint64, address));
                assertEq(emittedExpiry, newExpiry, "Renew Event expiry mismatch");
                assertEq(emittedRenewer, address(this), "Renew Event renewer mismatch");
                foundRenewed = true;
                break;
            }
        }
        assertTrue(foundRenewed, "Controller NameRenewed event not found");
    }

    function test_onRenew_noEvent_whenNotOwner() public {
        // Setup: Register a name owned by 'user'. Do not eject.
        tokenId = _registerName(user);
        assertEq(registry.ownerOf(tokenId), user, "Setup failed: User should own token");

        // Set the controller as the token observer
        registry.grantRootRoles(ROLE_SET_TOKEN_OBSERVER_ADMIN, address(this));
        bytes32 resource = registry.getTokenIdResource(tokenId);
        registry.grantRoles(resource, ROLE_SET_TOKEN_OBSERVER, user);
        
        vm.prank(user); 
        registry.setTokenObserver(tokenId, ITokenObserver(address(controller)));
        vm.stopPrank();

        vm.recordLogs();
        // Renew the token using the registry (needs appropriate roles/pranking)
        registry.grantRoles(resource, ROLE_RENEW, user);
        vm.prank(user);
        uint64 newExpiry = uint64(block.timestamp + expiryDuration * 2);
        registry.renew(tokenId, newExpiry);
        vm.stopPrank();

        // Check that *no* NameRenewed event was emitted *by the controller*
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundControllerRenewEvent = false;
        for(uint i = 0; i < entries.length; i++) {
             if(entries[i].topics[0] == keccak256("NameRenewed(uint256,uint64,address)") && entries[i].emitter == address(controller)) {
                 foundControllerRenewEvent = true;
                 break;
             }
         }
        assertFalse(foundControllerRenewEvent, "Controller NameRenewed event should not be emitted when it's not the owner");
    }

    function test_onRelinquish_doesNothing() public {
        // Setup: Register and eject. Controller owns the token.
        tokenId = _registerName(address(this));
        _ejectName(tokenId, l1Owner, l1Subregistry, l1Resolver);
        assertEq(registry.ownerOf(tokenId), address(controller), "Setup failed: Controller doesn't own token after eject");
        
        // Set the controller as the token observer
        registry.grantRootRoles(ROLE_SET_TOKEN_OBSERVER_ADMIN, address(this));
        bytes32 resource = registry.getTokenIdResource(tokenId);
        registry.grantRoles(resource, ROLE_SET_TOKEN_OBSERVER, address(this));
        registry.setTokenObserver(tokenId, ITokenObserver(address(controller)));

        // Directly call the onRelinquish hook on the controller (simulating registry call)
        // It should not revert and emit no events.
        vm.recordLogs();
        controller.onRelinquish(tokenId, address(controller)); // Pass controller as relinquishedBy for consistency
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0, "onRelinquish should not emit events");
    }
}