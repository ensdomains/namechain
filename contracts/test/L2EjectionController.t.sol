// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

import "../src/L2/L2EjectionController.sol";
import "../src/common/IStandardRegistry.sol";
import "../src/common/IRegistry.sol";
import "../src/common/ITokenObserver.sol";
import "../src/common/RegistryDatastore.sol";
import "../src/common/IRegistryDatastore.sol";
import "../src/common/IRegistryMetadata.sol";
import "../src/common/NameUtils.sol";
import "../src/common/ETHRegistry.sol";
import "../src/common/IEjectionController.sol";
import {RegistryRolesMixin} from "../src/common/RegistryRolesMixin.sol";
import {EnhancedAccessControl} from "../src/common/EnhancedAccessControl.sol";

// Mock implementation of IRegistryMetadata
contract MockRegistryMetadata is IRegistryMetadata {
    function tokenUri(uint256) external pure override returns (string memory) {
        return "";
    }
}

// Concrete implementation of ETHRegistry for testing
contract TestETHRegistry is ETHRegistry {
    constructor(
        IRegistryDatastore _datastore,
        IRegistryMetadata _registryMetadata,
        IEjectionController _ejectionController
    ) ETHRegistry(_datastore, _registryMetadata, _ejectionController) {}

    // Make register method public for testing
    function register(string calldata label, address owner, IRegistry registry, address resolver, uint256 roleBitmap, uint64 expires)
        public
        override
        onlyRootRoles(ROLE_REGISTRAR)
        returns (uint256 tokenId)
    {
        return super.register(label, owner, registry, resolver, roleBitmap, expires);
    }
}

// Mock implementation of IEjectionController
contract MockEjectionController is IEjectionController {
    // Track calls to onRenew
    bool public renewCalled;
    uint256 public lastRenewedTokenId;
    uint64 public lastRenewedExpires;
    address public lastRenewedBy;

    // Track calls to onRelinquish
    bool public relinquishCalled;
    uint256 public lastRelinquishedTokenId;
    address public lastRelinquishedBy;

    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external override {
        renewCalled = true;
        lastRenewedTokenId = tokenId;
        lastRenewedExpires = expires;
        lastRenewedBy = renewedBy;
    }

    function onRelinquish(uint256 tokenId, address relinquishedBy) external override {
        relinquishCalled = true;
        lastRelinquishedTokenId = tokenId;
        lastRelinquishedBy = relinquishedBy;
    }
}

contract TestL2EjectionController is Test, ERC1155Holder, RegistryRolesMixin {
    // Import constants from RegistryRolesMixin and EnhancedAccessControl
    bytes32 constant ROOT_RESOURCE = bytes32(0);
    uint256 constant ALL_ROLES = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    
    L2EjectionController controller;
    TestETHRegistry registry;
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
    uint256 labelHash;
    uint256 tokenId;
    uint64 expiryDuration = 86400; // 1 day

    function setUp() public {
        datastore = new RegistryDatastore();
        registryMetadata = new MockRegistryMetadata();
        
        // First create temporary controller
        L2EjectionController tempController = new L2EjectionController(IStandardRegistry(address(0)));
        
        // Deploy registry with the controller as IEjectionController
        registry = new TestETHRegistry(datastore, registryMetadata, IEjectionController(address(tempController)));
        
        // Now deploy the real controller with the correct registry
        controller = new L2EjectionController(registry);
        
        // Update registry to use the real controller
        registry.grantRootRoles(ROLE_SET_EJECTION_CONTROLLER, address(this));
        registry.setEjectionController(IEjectionController(address(controller)));
        
        // Set up for testing
        labelHash = NameUtils.labelToCanonicalId(label);
        
        // Grant this test contract the registrar role so we can register names
        registry.grantRootRoles(ROLE_REGISTRAR, address(this));
        
        // Register a test name
        uint64 expires = uint64(block.timestamp + expiryDuration);
        tokenId = registry.register(label, user, registry, address(0), ALL_ROLES, expires);
    }

    function test_constructor() public view {
        assertEq(address(controller.registry()), address(registry));
    }

    function test_eject_flow_via_transfer() public {
        // Prepare the data for ejection
        bytes memory ejectionData = abi.encode(l1Owner, l1Subregistry, l1Resolver);
        
        // Make sure user still owns the token
        assertEq(registry.ownerOf(tokenId), user);
        
        // User transfers the token to the ejection controller
        vm.recordLogs();
        vm.prank(user);
        registry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
        
        // Verify NameEjectedToL1 event was emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundEjectedEvent = false;
        
        for(uint i = 0; i < entries.length; i++) {
            // Check for event from controller
            if(entries[i].emitter == address(controller) && 
               entries[i].topics[0] == keccak256("NameEjectedToL1(uint256,address,address,address,uint64)")) {
                
                // Verify tokenId in topics
                assertEq(uint256(entries[i].topics[1]), tokenId, "Event tokenId mismatch");
                
                // Decode remaining data fields
                (address emittedL1Owner, address emittedL1Subregistry, address emittedL1Resolver, ) = 
                    abi.decode(entries[i].data, (address, address, address, uint64));
                
                assertEq(emittedL1Owner, l1Owner, "Event l1Owner mismatch");
                assertEq(emittedL1Subregistry, l1Subregistry, "Event l1Subregistry mismatch");
                assertEq(emittedL1Resolver, l1Resolver, "Event l1Resolver mismatch");
                foundEjectedEvent = true;
                break;
            }
        }
        
        assertTrue(foundEjectedEvent, "NameEjectedToL1 event not found");
        
        // Verify subregistry is cleared after ejection
        (address subregAddr, , ) = datastore.getSubregistry(tokenId);
        assertEq(subregAddr, address(0), "Subregistry not cleared after ejection");
        
        // Verify token is now owned by the controller
        assertEq(registry.ownerOf(tokenId), address(controller), "Token should be owned by the controller");
    }

    function test_completeMigrationFromL1() public {
        // First eject the name so the controller owns it
        bytes memory ejectionData = abi.encode(l1Owner, l1Subregistry, l1Resolver);
        vm.prank(user);
        registry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
        
        // Verify controller owns the token
        assertEq(registry.ownerOf(tokenId), address(controller), "Controller should own the token");
        
        vm.recordLogs();
        // Call the migration function
        controller.completeMigrationFromL1(tokenId, l2Owner, l2Subregistry, l2Resolver);
        
        // Verify event emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundMigratedEvent = false;
        
        for(uint i = 0; i < entries.length; i++) {
            // Check for event from controller
            if(entries[i].emitter == address(controller) && 
               entries[i].topics[0] == keccak256("NameMigratedToL2(uint256,address,address,address)")) {
                
                // Verify tokenId in topics
                assertEq(uint256(entries[i].topics[1]), tokenId, "Event tokenId mismatch");
                
                // Decode remaining data fields
                (address emittedL2Owner, address emittedL2Subregistry, address emittedL2Resolver) = 
                    abi.decode(entries[i].data, (address, address, address));
                
                assertEq(emittedL2Owner, l2Owner, "Event l2Owner mismatch");
                assertEq(emittedL2Subregistry, l2Subregistry, "Event l2Subregistry mismatch");
                assertEq(emittedL2Resolver, l2Resolver, "Event l2Resolver mismatch");
                foundMigratedEvent = true;
                break;
            }
        }
        
        assertTrue(foundMigratedEvent, "NameMigratedToL2 event not found");
        
        // Verify subregistry and resolver were set correctly
        IRegistry subregAddr = registry.getSubregistry(label);
        assertEq(address(subregAddr), l2Subregistry, "Subregistry not set correctly after migration");
        
        address resolverAddr = registry.getResolver(label);
        assertEq(resolverAddr, l2Resolver, "Resolver not set correctly after migration");
        
        // Verify token ownership transferred
        assertEq(registry.ownerOf(tokenId), l2Owner, "Token ownership not transferred after migration");
    }

    function test_Revert_completeMigrationFromL1_notOwner() public {
        // Do not eject the name, so the controller doesn't own it
        // (user from setUp still owns it)
        
        // Expect revert with NotTokenOwner error
        vm.expectRevert(abi.encodeWithSelector(L2EjectionController.NotTokenOwner.selector, tokenId));
        controller.completeMigrationFromL1(tokenId, l2Owner, l2Subregistry, l2Resolver);
    }

    function test_supportsInterface() public view {
        assertTrue(controller.supportsInterface(type(ITokenObserver).interfaceId));
        assertTrue(controller.supportsInterface(type(IERC1155Receiver).interfaceId));
        assertFalse(controller.supportsInterface(0x12345678));
    }

    function test_onERC1155BatchReceived() public {
        // Register two more names
        uint64 expires = uint64(block.timestamp + expiryDuration);
        string memory label2 = "test2";
        string memory label3 = "test3";
        uint256 tokenId2 = registry.register(label2, user, registry, address(0), ALL_ROLES, expires);
        uint256 tokenId3 = registry.register(label3, user, registry, address(0), ALL_ROLES, expires);
        
        // Setup data for the batch transfer
        bytes memory ejectionData = abi.encode(l1Owner, l1Subregistry, l1Resolver);
        
        // Create batch of tokens to transfer
        uint256[] memory ids = new uint256[](2);
        ids[0] = tokenId2;
        ids[1] = tokenId3;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        
        // Perform the batch transfer
        vm.startPrank(user);
        registry.safeBatchTransferFrom(user, address(controller), ids, amounts, ejectionData);
        vm.stopPrank();
        
        // Verify tokens are now owned by the controller
        assertEq(registry.ownerOf(ids[0]), address(controller), "First token should be owned by controller");
        assertEq(registry.ownerOf(ids[1]), address(controller), "Second token should be owned by controller");
        
        // Verify subregistry was cleared for both tokens
        (address subregAddr1, , ) = datastore.getSubregistry(ids[0]);
        assertEq(subregAddr1, address(0), "Subregistry not cleared for token 1");
        
        (address subregAddr2, , ) = datastore.getSubregistry(ids[1]);
        assertEq(subregAddr2, address(0), "Subregistry not cleared for token 2");
    }

    function test_onRenew() public {
        // First eject the name so the controller owns it
        bytes memory ejectionData = abi.encode(l1Owner, l1Subregistry, l1Resolver);
        vm.prank(user);
        registry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
        
        // Verify controller owns the token
        assertEq(registry.ownerOf(tokenId), address(controller), "Controller should own the token");
        
        // Instead of using registry.renew, call controller.onRenew directly
        vm.recordLogs();
        uint64 newExpiry = uint64(block.timestamp + expiryDuration * 2);
        controller.onRenew(tokenId, newExpiry, address(this));
        
        // Verify event was emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundRenewedEvent = false;
        
        for(uint i = 0; i < entries.length; i++) {
            // Check for NameRenewed event
            if(entries[i].emitter == address(controller) && 
               entries[i].topics[0] == keccak256("NameRenewed(uint256,uint64,address)")) {
                
                // Verify tokenId in topics
                assertEq(uint256(entries[i].topics[1]), tokenId, "Event tokenId mismatch");
                
                // Decode data
                (uint64 emittedExpiry, address renewedBy) = abi.decode(entries[i].data, (uint64, address));
                
                assertEq(emittedExpiry, newExpiry, "Event expires mismatch");
                assertEq(renewedBy, address(this), "Event renewedBy mismatch");
                foundRenewedEvent = true;
                break;
            }
        }
        
        assertTrue(foundRenewedEvent, "NameRenewed event not found");
    }

    function test_onRelinquish() public {
        // First eject the name so the controller owns it
        bytes memory ejectionData = abi.encode(l1Owner, l1Subregistry, l1Resolver);
        vm.prank(user);
        registry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
        
        // Verify controller owns the token
        assertEq(registry.ownerOf(tokenId), address(controller), "Controller should own the token");
        
        // Relinquish is called by the owner of the token, which is now the controller
        vm.prank(address(controller));
        registry.relinquish(tokenId);
        
        // Verify token no longer exists
        (address subregAddr, uint64 expires, ) = datastore.getSubregistry(tokenId);
        assertEq(subregAddr, address(0), "Subregistry should be cleared");
        assertEq(expires, 0, "Expiry should be cleared");
    }
}