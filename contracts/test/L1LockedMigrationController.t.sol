// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {INameWrapper, CANNOT_UNWRAP, CANNOT_BURN_FUSES, CANNOT_TRANSFER, CANNOT_SET_RESOLVER, CANNOT_SET_TTL, CANNOT_CREATE_SUBDOMAIN, CANNOT_APPROVE} from "@ens/contracts/wrapper/INameWrapper.sol";
import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

import {L1LockedMigrationController} from "../src/L1/L1LockedMigrationController.sol";
import {L1BridgeController} from "../src/L1/L1BridgeController.sol";
import {IRegistry} from "../src/common/IRegistry.sol";
import {MigratedWrappedNameRegistry} from "../src/L1/MigratedWrappedNameRegistry.sol";
import {VerifiableFactory} from "../lib/verifiable-factory/src/VerifiableFactory.sol";
import {TransferData, MigrationData} from "../src/common/TransferData.sol";
import {IRegistryDatastore} from "../src/common/IRegistryDatastore.sol";
import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {IRegistryMetadata} from "../src/common/IRegistryMetadata.sol";
import {IPermissionedRegistry} from "../src/common/IPermissionedRegistry.sol";
import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";
import {IBridge, LibBridgeRoles} from "../src/common/IBridge.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";
import {NameUtils} from "../src/common/NameUtils.sol";
import {MockPermissionedRegistry} from "./mocks/MockPermissionedRegistry.sol";
import {EnhancedAccessControl, LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";

contract MockNameWrapper {
    mapping(uint256 => uint32) public fuses;
    mapping(uint256 => uint64) public expiries;
    mapping(uint256 => address) public owners;
    
    function setFuseData(uint256 tokenId, uint32 _fuses, uint64 _expiry) external {
        fuses[tokenId] = _fuses;
        expiries[tokenId] = _expiry;
    }
    
    function getData(uint256 id) external view returns (address, uint32, uint64) {
        return (owners[id], fuses[id], expiries[id]);
    }
    
    function setFuses(bytes32 node, uint16 fusesToBurn) external returns (uint32) {
        uint256 tokenId = uint256(node);
        fuses[tokenId] = fuses[tokenId] | fusesToBurn;
        return fuses[tokenId];
    }
}

contract MockBaseRegistrar {
    // Empty mock - we'll force cast it to IBaseRegistrar
}

contract MockBridge is IBridge {
    bytes public lastMessage;
    
    function sendMessage(bytes memory message) external override {
        lastMessage = message;
    }
    
    function getLastMessage() external view returns (bytes memory) {
        return lastMessage;
    }
}

contract MockUniversalResolver {
    function findResolver(bytes calldata) external pure returns (address, bytes32, uint256) {
        return (address(0xDEAD), bytes32(0), 0);
    }
}

contract MockRegistryMetadata is IRegistryMetadata {
    function tokenUri(uint256) external pure override returns (string memory) {
        return "";
    }
}

contract TestL1LockedMigrationController is Test, ERC1155Holder {
    L1LockedMigrationController controller;
    MockNameWrapper nameWrapper;
    MockBaseRegistrar baseRegistrar;
    MockBridge bridge;
    L1BridgeController bridgeController;
    RegistryDatastore rootDatastore;
    RegistryDatastore ethDatastore;
    MockRegistryMetadata metadata;
    MockUniversalResolver universalResolver;
    MockPermissionedRegistry rootRegistry;
    MockPermissionedRegistry ethRegistry;
    VerifiableFactory factory;
    MigratedWrappedNameRegistry implementation;
    
    address owner = address(this);
    address user = address(0x1234);
    
    string testLabel = "test";
    uint256 testTokenId;


    function setUp() public {
        nameWrapper = new MockNameWrapper();
        baseRegistrar = new MockBaseRegistrar();
        bridge = new MockBridge();
        rootDatastore = new RegistryDatastore();
        ethDatastore = new RegistryDatastore();
        metadata = new MockRegistryMetadata();
        universalResolver = new MockUniversalResolver();
        
        // Deploy factory and implementation
        factory = new VerifiableFactory();
        implementation = new MigratedWrappedNameRegistry();
        
        // Setup root and eth registries
        rootRegistry = new MockPermissionedRegistry(rootDatastore, metadata, owner, LibEACBaseRoles.ALL_ROLES);
        ethRegistry = new MockPermissionedRegistry(ethDatastore, metadata, owner, LibEACBaseRoles.ALL_ROLES);
        
        // Register eth as a subregistry of root
        rootRegistry.register("eth", owner, IRegistry(address(ethRegistry)), address(0), LibRegistryRoles.ROLE_SET_SUBREGISTRY, uint64(block.timestamp + 365 days));
        
        // Setup bridge controller with proper hierarchy
        bridgeController = new L1BridgeController(ethRegistry, bridge, rootRegistry);
        
        // Grant necessary roles
        ethRegistry.grantRootRoles(LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_BURN, address(bridgeController));
        bridgeController.grantRootRoles(LibBridgeRoles.ROLE_EJECTOR, address(controller));
        
        controller = new L1LockedMigrationController(
            IBaseRegistrar(address(baseRegistrar)),
            INameWrapper(address(nameWrapper)),
            bridge,
            bridgeController,
            factory,
            address(implementation),
            ethDatastore,
            metadata,
            IUniversalResolver(address(universalResolver))
        );
        
        // Grant bridge controller permission to be called by migration controller
        bridgeController.grantRootRoles(LibBridgeRoles.ROLE_EJECTOR, address(controller));
        
        testTokenId = uint256(keccak256(bytes(testLabel)));
    }

    function test_onERC1155Received_locked_name() public {
        // Setup locked name (CANNOT_UNWRAP is set, CANNOT_BURN_FUSES is NOT set)
        uint32 lockedFuses = CANNOT_UNWRAP;
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));
        
        // Prepare migration data
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                label: testLabel,
                owner: user,
                subregistry: address(0), // Will be created by factory
                resolver: address(0xABCD),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY
            }),
            toL1: true,
            dnsEncodedName: NameUtils.dnsEncodeEthLabel("test"), // DNS encode "test.eth"
            salt: abi.encodePacked(testLabel, block.timestamp)
        });
        
        bytes memory data = abi.encode(migrationData);
        
        // Call onERC1155Received
        vm.prank(address(nameWrapper));
        bytes4 selector = controller.onERC1155Received(owner, owner, testTokenId, 1, data);
        
        // Verify selector returned
        assertEq(selector, controller.onERC1155Received.selector, "Should return correct selector");
        
        // Verify all required fuses were burnt
        (, uint32 newFuses, ) = nameWrapper.getData(testTokenId);
        assertTrue((newFuses & CANNOT_BURN_FUSES) != 0, "CANNOT_BURN_FUSES should be burnt");
        assertTrue((newFuses & CANNOT_TRANSFER) != 0, "CANNOT_TRANSFER should be burnt");
        assertTrue((newFuses & CANNOT_UNWRAP) != 0, "CANNOT_UNWRAP should be burnt");
        assertTrue((newFuses & CANNOT_SET_RESOLVER) != 0, "CANNOT_SET_RESOLVER should be burnt");
        assertTrue((newFuses & CANNOT_SET_TTL) != 0, "CANNOT_SET_TTL should be burnt");
        assertTrue((newFuses & CANNOT_CREATE_SUBDOMAIN) != 0, "CANNOT_CREATE_SUBDOMAIN should be burnt");
        assertTrue((newFuses & CANNOT_APPROVE) != 0, "CANNOT_APPROVE should be burnt");
    }

    function test_onERC1155Received_always_removes_resolver_roles() public {
        // Setup locked name (CANNOT_BURN_FUSES not set so migration can proceed)
        uint32 lockedFuses = CANNOT_UNWRAP;
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));
        
        // Prepare migration data with resolver roles
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                label: testLabel,
                owner: user,
                subregistry: address(0), // Will be created by factory
                resolver: address(0xABCD),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER | 
                           LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN | 
                           LibRegistryRoles.ROLE_SET_SUBREGISTRY
            }),
            toL1: true,
            dnsEncodedName: NameUtils.dnsEncodeEthLabel("test"), // DNS encode "test.eth"
            salt: abi.encodePacked(testLabel, block.timestamp)
        });
        
        bytes memory data = abi.encode(migrationData);
        
        // Call onERC1155Received
        vm.prank(address(nameWrapper));
        controller.onERC1155Received(owner, owner, testTokenId, 1, data);
        
        // Get the registered name and check roles
        (uint256 registeredTokenId,,) = ethRegistry.getNameData(testLabel);
        uint256 resource = ethRegistry.testGetResourceFromTokenId(registeredTokenId);
        uint256 userRoles = ethRegistry.roles(resource, user);
        
        // Verify resolver roles were removed (always removed now since CANNOT_SET_RESOLVER is always burnt)
        assertTrue((userRoles & LibRegistryRoles.ROLE_SET_RESOLVER) == 0, "ROLE_SET_RESOLVER should always be removed");
        assertTrue((userRoles & LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN) == 0, "ROLE_SET_RESOLVER_ADMIN should always be removed");
        assertTrue((userRoles & LibRegistryRoles.ROLE_SET_SUBREGISTRY) != 0, "ROLE_SET_SUBREGISTRY should remain");
    }

    function test_Revert_onERC1155Received_not_locked() public {
        // Setup unlocked name (CANNOT_UNWRAP is NOT set)
        uint32 unlockedFuses = 0;
        nameWrapper.setFuseData(testTokenId, unlockedFuses, uint64(block.timestamp + 86400));
        
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                label: testLabel,
                owner: user,
                subregistry: address(0), // Will be created by factory
                resolver: address(0xABCD),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER
            }),
            toL1: true,
            dnsEncodedName: NameUtils.dnsEncodeEthLabel("test"), // DNS encode "test.eth"
            salt: abi.encodePacked(testLabel, block.timestamp)
        });
        
        bytes memory data = abi.encode(migrationData);
        
        // Should revert because name is not locked
        vm.expectRevert(L1LockedMigrationController.NameNotLocked.selector);
        vm.prank(address(nameWrapper));
        controller.onERC1155Received(owner, owner, testTokenId, 1, data);
    }

    function test_Revert_cannot_burn_fuses_already_set() public {
        // Setup with CANNOT_BURN_FUSES already set - migration should fail
        uint32 fuses = CANNOT_UNWRAP | CANNOT_BURN_FUSES;
        nameWrapper.setFuseData(testTokenId, fuses, uint64(block.timestamp + 86400));
        
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                label: testLabel,
                owner: user,
                subregistry: address(0), // Will be created by factory
                resolver: address(0xABCD),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER
            }),
            toL1: true,
            dnsEncodedName: NameUtils.dnsEncodeEthLabel("test"), // DNS encode "test.eth"
            salt: abi.encodePacked(testLabel, block.timestamp)
        });
        
        bytes memory data = abi.encode(migrationData);
        
        // Should revert because CANNOT_BURN_FUSES is already set
        vm.expectRevert(L1LockedMigrationController.InconsistentFusesState.selector);
        vm.prank(address(nameWrapper));
        controller.onERC1155Received(owner, owner, testTokenId, 1, data);
    }

    function test_Revert_token_id_mismatch() public {
        // Setup locked name
        uint32 lockedFuses = CANNOT_UNWRAP;
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));
        
        // Use wrong label that doesn't match tokenId
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                label: "wronglabel", // This won't match testTokenId
                owner: user,
                subregistry: address(0), // Will be created by factory
                resolver: address(0xABCD),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER
            }),
            toL1: true,
            dnsEncodedName: NameUtils.dnsEncodeEthLabel("wronglabel"), // DNS encode "wronglabel.eth"
            salt: abi.encodePacked(testLabel, block.timestamp)
        });
        
        bytes memory data = abi.encode(migrationData);
        
        // Should revert due to token ID mismatch
        uint256 expectedTokenId = uint256(keccak256(bytes("wronglabel")));
        vm.expectRevert(abi.encodeWithSelector(L1LockedMigrationController.TokenIdMismatch.selector, testTokenId, expectedTokenId));
        vm.prank(address(nameWrapper));
        controller.onERC1155Received(owner, owner, testTokenId, 1, data);
    }

    function test_Revert_unauthorized_caller() public {
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                label: testLabel,
                owner: user,
                subregistry: address(0), // Will be created by factory
                resolver: address(0xABCD),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER
            }),
            toL1: true,
            dnsEncodedName: NameUtils.dnsEncodeEthLabel("test"), // DNS encode "test.eth"
            salt: abi.encodePacked(testLabel, block.timestamp)
        });
        
        bytes memory data = abi.encode(migrationData);
        
        // Call from wrong address (not nameWrapper)
        vm.expectRevert(abi.encodeWithSelector(L1LockedMigrationController.UnauthorizedCaller.selector, address(this)));
        controller.onERC1155Received(owner, owner, testTokenId, 1, data);
    }

    function test_onERC1155BatchReceived() public {
        // Setup multiple locked names
        string[] memory labels = new string[](3);
        labels[0] = "test1";
        labels[1] = "test2";
        labels[2] = "test3";
        
        uint256[] memory tokenIds = new uint256[](3);
        MigrationData[] memory migrationDataArray = new MigrationData[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            tokenIds[i] = uint256(keccak256(bytes(labels[i])));
            
            // Setup locked name (CANNOT_BURN_FUSES not set)
            uint32 lockedFuses = CANNOT_UNWRAP;
            nameWrapper.setFuseData(tokenIds[i], lockedFuses, uint64(block.timestamp + 86400));
            
            // DNS encode each label as .eth domain
            bytes memory dnsEncodedName;
            if (i == 0) {
                dnsEncodedName = NameUtils.dnsEncodeEthLabel("test1");
            } else if (i == 1) {
                dnsEncodedName = NameUtils.dnsEncodeEthLabel("test2");
            } else {
                dnsEncodedName = NameUtils.dnsEncodeEthLabel("test3");
            }
            
            migrationDataArray[i] = MigrationData({
                transferData: TransferData({
                    label: labels[i],
                    owner: user,
                    subregistry: address(0), // Will be created by factory
                    resolver: address(uint160(0xABCD + i)),
                    expires: uint64(block.timestamp + 86400 * (i + 1)),
                    roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER
                }),
                toL1: true,
                dnsEncodedName: dnsEncodedName,
                salt: abi.encodePacked(labels[i], block.timestamp, i)
            });
        }
        
        bytes memory data = abi.encode(migrationDataArray);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amounts[1] = amounts[2] = 1;
        
        // Call batch receive
        vm.prank(address(nameWrapper));
        bytes4 selector = controller.onERC1155BatchReceived(owner, owner, tokenIds, amounts, data);
        
        assertEq(selector, controller.onERC1155BatchReceived.selector, "Should return correct selector");
        
        // Verify all names were processed with all fuses burnt
        for (uint256 i = 0; i < 3; i++) {
            (, uint32 newFuses, ) = nameWrapper.getData(tokenIds[i]);
            assertTrue((newFuses & CANNOT_BURN_FUSES) != 0, "CANNOT_BURN_FUSES should be burnt");
            assertTrue((newFuses & CANNOT_TRANSFER) != 0, "CANNOT_TRANSFER should be burnt");
            assertTrue((newFuses & CANNOT_UNWRAP) != 0, "CANNOT_UNWRAP should be burnt");
            assertTrue((newFuses & CANNOT_SET_RESOLVER) != 0, "CANNOT_SET_RESOLVER should be burnt");
            assertTrue((newFuses & CANNOT_SET_TTL) != 0, "CANNOT_SET_TTL should be burnt");
            assertTrue((newFuses & CANNOT_CREATE_SUBDOMAIN) != 0, "CANNOT_CREATE_SUBDOMAIN should be burnt");
            assertTrue((newFuses & CANNOT_APPROVE) != 0, "CANNOT_APPROVE should be burnt");
        }
    }


    function test_subregistry_creation() public {
        // Setup locked name (CANNOT_BURN_FUSES not set)
        uint32 lockedFuses = CANNOT_UNWRAP;
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));
        
        // Prepare migration data with unique salt
        bytes memory saltData = abi.encodePacked(testLabel, uint256(999));
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                label: testLabel,
                owner: user,
                subregistry: address(0), // Will be created by factory
                resolver: address(0xABCD),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER
            }),
            toL1: true,
            dnsEncodedName: NameUtils.dnsEncodeEthLabel("test"), // DNS encode "test.eth"
            salt: saltData
        });
        
        bytes memory data = abi.encode(migrationData);
        
        // Call onERC1155Received
        vm.prank(address(nameWrapper));
        controller.onERC1155Received(owner, owner, testTokenId, 1, data);
        
        // Verify a subregistry was created
        address actualSubregistry = address(ethRegistry.getSubregistry(testLabel));
        assertTrue(actualSubregistry != address(0), "Subregistry should be created");
        
        // Verify it's a proxy pointing to our implementation
        // The factory creates a proxy, so we can verify it's pointing to the right implementation
        MigratedWrappedNameRegistry migratedRegistry = MigratedWrappedNameRegistry(actualSubregistry);
        assertEq(address(migratedRegistry.universalResolver()), address(universalResolver), "Should have correct universal resolver");
    }

    function test_3LD_migration_with_parent_migrated() public {
        // First, migrate the parent domain "parent"
        string memory parentLabel = "parent";
        uint256 parentTokenId = uint256(keccak256(bytes(parentLabel)));
        
        // Setup locked parent name
        uint32 parentLockedFuses = CANNOT_UNWRAP;
        nameWrapper.setFuseData(parentTokenId, parentLockedFuses, uint64(block.timestamp + 86400));
        
        // Prepare parent migration data
        MigrationData memory parentMigrationData = MigrationData({
            transferData: TransferData({
                label: parentLabel,
                owner: user,
                subregistry: address(0), // Will be created by factory
                resolver: address(0xABCD),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_SUBREGISTRY | LibRegistryRoles.ROLE_REGISTRAR
            }),
            toL1: true,
            dnsEncodedName: NameUtils.dnsEncodeEthLabel("parent"), // DNS encode "parent.eth"
            salt: abi.encodePacked(parentLabel, block.timestamp)
        });
        
        bytes memory parentData = abi.encode(parentMigrationData);
        
        // Migrate parent first
        vm.prank(address(nameWrapper));
        controller.onERC1155Received(owner, owner, parentTokenId, 1, parentData);
        
        // Verify parent was registered
        (uint256 registeredParentTokenId,,) = ethRegistry.getNameData(parentLabel);
        assertTrue(registeredParentTokenId != 0, "Parent should be registered");
        
        // Now migrate the 3LD "sub.parent"
        string memory subLabel = "sub";
        // For 3LD, the tokenId is still the hash of just the label "sub"
        uint256 subTokenId = uint256(keccak256(bytes(subLabel)));
        
        // Setup locked 3LD name
        uint32 subLockedFuses = CANNOT_UNWRAP;
        nameWrapper.setFuseData(subTokenId, subLockedFuses, uint64(block.timestamp + 86400));
        
        // Prepare 3LD migration data with DNS-encoded name "sub.parent"
        MigrationData memory subMigrationData = MigrationData({
            transferData: TransferData({
                label: subLabel,
                owner: user,
                subregistry: address(0), // Will be created by factory
                resolver: address(0xDEF1),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER
            }),
            toL1: true,
            dnsEncodedName: NameCoder.encode("sub.parent.eth"), // DNS encode "sub.parent.eth"
            salt: abi.encodePacked(subLabel, parentLabel, block.timestamp)
        });
        
        bytes memory subData = abi.encode(subMigrationData);
        
        // Migrate 3LD
        vm.prank(address(nameWrapper));
        controller.onERC1155Received(owner, owner, subTokenId, 1, subData);
        
        // Get parent's subregistry to verify the sub was registered there
        IRegistry parentSubregistry = ethRegistry.getSubregistry(parentLabel);
        assertTrue(address(parentSubregistry) != address(0), "Parent should have a subregistry");
        
        // Cast to IPermissionedRegistry to access getNameData
        IPermissionedRegistry parentRegistry = IPermissionedRegistry(address(parentSubregistry));
        (uint256 registeredSubTokenId,,) = parentRegistry.getNameData(subLabel);
        assertTrue(registeredSubTokenId != 0, "Sub should be registered in parent's registry");
        
        // Verify the sub's resolver is set correctly
        address subResolver = parentSubregistry.getResolver(subLabel);
        assertEq(subResolver, address(0xDEF1), "Sub resolver should be set correctly");
    }

    function test_Revert_3LD_migration_without_parent() public {
        // Try to migrate a 3LD "sub.nonexistent" without migrating "nonexistent" first
        string memory subLabel = "sub";
        uint256 subTokenId = uint256(keccak256(bytes(subLabel)));
        
        // Setup locked 3LD name
        uint32 subLockedFuses = CANNOT_UNWRAP;
        nameWrapper.setFuseData(subTokenId, subLockedFuses, uint64(block.timestamp + 86400));
        
        // Prepare 3LD migration data with DNS-encoded name "sub.nonexistent"
        MigrationData memory subMigrationData = MigrationData({
            transferData: TransferData({
                label: subLabel,
                owner: user,
                subregistry: address(0),
                resolver: address(0xDEF1),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER
            }),
            toL1: true,
            dnsEncodedName: NameCoder.encode("sub.nonexistent.eth"), // DNS encode "sub.nonexistent.eth"
            salt: abi.encodePacked(subLabel, "nonexistent", block.timestamp)
        });
        
        bytes memory subData = abi.encode(subMigrationData);
        
        // Should revert because parent "nonexistent" hasn't been migrated
        // The offset should be 4 (pointing to "nonexistent" label start)
        vm.expectRevert(abi.encodeWithSelector(L1BridgeController.ParentNotMigrated.selector, 
            NameCoder.encode("sub.nonexistent.eth"), 
            4
        ));
        vm.prank(address(nameWrapper));
        controller.onERC1155Received(owner, owner, subTokenId, 1, subData);
    }

    function test_4LD_migration_with_grandparent_and_parent() public {
        // First, migrate the grandparent domain "grandparent"
        string memory grandparentLabel = "grandparent";
        uint256 grandparentTokenId = uint256(keccak256(bytes(grandparentLabel)));
        
        // Setup and migrate grandparent
        uint32 grandparentLockedFuses = CANNOT_UNWRAP;
        nameWrapper.setFuseData(grandparentTokenId, grandparentLockedFuses, uint64(block.timestamp + 86400));
        
        MigrationData memory grandparentMigrationData = MigrationData({
            transferData: TransferData({
                label: grandparentLabel,
                owner: user,
                subregistry: address(0),
                resolver: address(0xAAAA),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_SUBREGISTRY | LibRegistryRoles.ROLE_REGISTRAR
            }),
            toL1: true,
            dnsEncodedName: NameUtils.dnsEncodeEthLabel("grandparent"), // DNS encode "grandparent.eth"
            salt: abi.encodePacked(grandparentLabel, "1")
        });
        
        vm.prank(address(nameWrapper));
        controller.onERC1155Received(owner, owner, grandparentTokenId, 1, abi.encode(grandparentMigrationData));
        
        // Get grandparent's subregistry
        IRegistry grandparentSubregistry = ethRegistry.getSubregistry(grandparentLabel);
        
        // Second, migrate the parent "parent.grandparent"
        string memory parentLabel = "parent";
        uint256 parentTokenId = uint256(keccak256(bytes(parentLabel)));
        
        uint32 parentLockedFuses = CANNOT_UNWRAP;
        nameWrapper.setFuseData(parentTokenId, parentLockedFuses, uint64(block.timestamp + 86400));
        
        MigrationData memory parentMigrationData = MigrationData({
            transferData: TransferData({
                label: parentLabel,
                owner: user,
                subregistry: address(0),
                resolver: address(0xBBBB),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_SUBREGISTRY | LibRegistryRoles.ROLE_REGISTRAR
            }),
            toL1: true,
            dnsEncodedName: NameCoder.encode("parent.grandparent.eth"), // DNS encode "parent.grandparent.eth"
            salt: abi.encodePacked(parentLabel, "2")
        });
        
        vm.prank(address(nameWrapper));
        controller.onERC1155Received(owner, owner, parentTokenId, 1, abi.encode(parentMigrationData));
        
        // Get parent's subregistry from grandparent's registry
        IRegistry parentSubregistry = grandparentSubregistry.getSubregistry(parentLabel);
        assertTrue(address(parentSubregistry) != address(0), "Parent should have a subregistry");
        
        // Finally, migrate the 4LD "child.parent.grandparent"
        string memory childLabel = "child";
        uint256 childTokenId = uint256(keccak256(bytes(childLabel)));
        
        uint32 childLockedFuses = CANNOT_UNWRAP;
        nameWrapper.setFuseData(childTokenId, childLockedFuses, uint64(block.timestamp + 86400));
        
        MigrationData memory childMigrationData = MigrationData({
            transferData: TransferData({
                label: childLabel,
                owner: user,
                subregistry: address(0),
                resolver: address(0xCCCC),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER
            }),
            toL1: true,
            dnsEncodedName: NameCoder.encode("child.parent.grandparent.eth"), // DNS encode "child.parent.grandparent.eth"
            salt: abi.encodePacked(childLabel, "3")
        });
        
        vm.prank(address(nameWrapper));
        controller.onERC1155Received(owner, owner, childTokenId, 1, abi.encode(childMigrationData));
        
        // Verify the child was registered in parent's registry
        IPermissionedRegistry parentPermissionedRegistry = IPermissionedRegistry(address(parentSubregistry));
        (uint256 registeredChildTokenId,,) = parentPermissionedRegistry.getNameData(childLabel);
        assertTrue(registeredChildTokenId != 0, "Child should be registered in parent's registry");
        
        // Verify resolver is set correctly
        address childResolver = parentSubregistry.getResolver(childLabel);
        assertEq(childResolver, address(0xCCCC), "Child resolver should be set correctly");
    }

    function test_Revert_4LD_migration_missing_intermediate_parent() public {
        // Migrate grandparent but not parent, then try to migrate 4LD
        string memory grandparentLabel = "grandparent";
        uint256 grandparentTokenId = uint256(keccak256(bytes(grandparentLabel)));
        
        // Setup and migrate grandparent
        uint32 grandparentLockedFuses = CANNOT_UNWRAP;
        nameWrapper.setFuseData(grandparentTokenId, grandparentLockedFuses, uint64(block.timestamp + 86400));
        
        MigrationData memory grandparentMigrationData = MigrationData({
            transferData: TransferData({
                label: grandparentLabel,
                owner: user,
                subregistry: address(0),
                resolver: address(0xAAAA),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_SUBREGISTRY | LibRegistryRoles.ROLE_REGISTRAR
            }),
            toL1: true,
            dnsEncodedName: NameUtils.dnsEncodeEthLabel("grandparent"), // DNS encode "grandparent.eth"
            salt: abi.encodePacked(grandparentLabel, block.timestamp)
        });
        
        vm.prank(address(nameWrapper));
        controller.onERC1155Received(owner, owner, grandparentTokenId, 1, abi.encode(grandparentMigrationData));
        
        // Now try to migrate 4LD without parent
        string memory childLabel = "child";
        uint256 childTokenId = uint256(keccak256(bytes(childLabel)));
        
        uint32 childLockedFuses = CANNOT_UNWRAP;
        nameWrapper.setFuseData(childTokenId, childLockedFuses, uint64(block.timestamp + 86400));
        
        MigrationData memory childMigrationData = MigrationData({
            transferData: TransferData({
                label: childLabel,
                owner: user,
                subregistry: address(0),
                resolver: address(0xCCCC),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER
            }),
            toL1: true,
            dnsEncodedName: NameCoder.encode("child.parent.grandparent.eth"), // DNS encode "child.parent.grandparent.eth"
            salt: abi.encodePacked(childLabel, "parent", "grandparent", block.timestamp)
        });
        
        // Should revert because intermediate parent hasn't been migrated
        bytes memory dnsName = NameCoder.encode("child.parent.grandparent.eth"); // "child.parent.grandparent.eth"
        vm.expectRevert(abi.encodeWithSelector(L1BridgeController.ParentNotMigrated.selector, dnsName, 6));
        vm.prank(address(nameWrapper));
        controller.onERC1155Received(owner, owner, childTokenId, 1, abi.encode(childMigrationData));
    }
}