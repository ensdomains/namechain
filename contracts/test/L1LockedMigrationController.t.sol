// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {INameWrapper, CANNOT_UNWRAP, CANNOT_BURN_FUSES, CANNOT_TRANSFER, CANNOT_SET_RESOLVER, CANNOT_SET_TTL, CANNOT_CREATE_SUBDOMAIN, CANNOT_APPROVE, IS_DOT_ETH} from "@ens/contracts/wrapper/INameWrapper.sol";
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
    RegistryDatastore datastore;
    MockRegistryMetadata metadata;
    MockUniversalResolver universalResolver;
    MockPermissionedRegistry registry;
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
        datastore = new RegistryDatastore();
        metadata = new MockRegistryMetadata();
        universalResolver = new MockUniversalResolver();
        
        // Deploy factory and implementation
        factory = new VerifiableFactory();
        implementation = new MigratedWrappedNameRegistry();
        
        // Setup eth registry
        registry = new MockPermissionedRegistry(datastore, metadata, owner, LibEACBaseRoles.ALL_ROLES);
        
        // Setup bridge controller
        bridgeController = new L1BridgeController(registry, bridge);
        
        // Grant necessary roles
        registry.grantRootRoles(LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_BURN, address(bridgeController));
        bridgeController.grantRootRoles(LibBridgeRoles.ROLE_EJECTOR, address(controller));
        
        controller = new L1LockedMigrationController(
            IBaseRegistrar(address(baseRegistrar)),
            INameWrapper(address(nameWrapper)),
            bridge,
            bridgeController,
            factory,
            address(implementation),
            datastore,
            metadata,
            IUniversalResolver(address(universalResolver))
        );
        
        // Grant bridge controller permission to be called by migration controller
        bridgeController.grantRootRoles(LibBridgeRoles.ROLE_EJECTOR, address(controller));
        
        testTokenId = uint256(keccak256(bytes(testLabel)));
    }

    function test_onERC1155Received_locked_name() public {
        // Setup locked name (CANNOT_UNWRAP is set, CANNOT_BURN_FUSES is NOT set)
        uint32 lockedFuses = CANNOT_UNWRAP | IS_DOT_ETH;
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

    function test_onERC1155Received_roles_based_on_fuses_not_input() public {
        // Setup locked name with no additional fuses burnt (CANNOT_SET_RESOLVER not burnt)
        uint32 lockedFuses = CANNOT_UNWRAP | IS_DOT_ETH;
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));
        
        // Prepare migration data - the roleBitmap should be ignored completely
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                label: testLabel,
                owner: user,
                subregistry: address(0), // Will be created by factory
                resolver: address(0xABCD),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_SUBREGISTRY // This should be completely ignored
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
        (uint256 registeredTokenId,,) = registry.getNameData(testLabel);
        uint256 resource = registry.testGetResourceFromTokenId(registeredTokenId);
        uint256 userRoles = registry.roles(resource, user);
        
        // Verify roles are granted based on fuses, not input
        // Since CANNOT_SET_RESOLVER is not burnt, user should have resolver roles
        assertTrue((userRoles & LibRegistryRoles.ROLE_SET_RESOLVER) != 0, "Should have ROLE_SET_RESOLVER based on fuses");
        assertTrue((userRoles & LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN) != 0, "Should have ROLE_SET_RESOLVER_ADMIN based on fuses");
        
        // Should always have these base roles but never registrar roles
        assertTrue((userRoles & LibRegistryRoles.ROLE_RENEW) != 0, "Should have ROLE_RENEW");
        assertTrue((userRoles & LibRegistryRoles.ROLE_RENEW_ADMIN) != 0, "Should have ROLE_RENEW_ADMIN");
        
        // Users never get registrar roles
        assertTrue((userRoles & LibRegistryRoles.ROLE_REGISTRAR) == 0, "Should NOT have ROLE_REGISTRAR");
        assertTrue((userRoles & LibRegistryRoles.ROLE_REGISTRAR_ADMIN) == 0, "Should NOT have ROLE_REGISTRAR_ADMIN");
        
        // Should NOT have the role from input data
        assertTrue((userRoles & LibRegistryRoles.ROLE_SET_SUBREGISTRY) == 0, "Should NOT have ROLE_SET_SUBREGISTRY from input");
    }

    function test_Revert_onERC1155Received_not_locked() public {
        // Setup unlocked name (CANNOT_UNWRAP is NOT set, but IS_DOT_ETH is set)
        uint32 unlockedFuses = IS_DOT_ETH;
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
        uint32 fuses = CANNOT_UNWRAP | CANNOT_BURN_FUSES | IS_DOT_ETH;
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
        uint32 lockedFuses = CANNOT_UNWRAP | IS_DOT_ETH;
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
            uint32 lockedFuses = CANNOT_UNWRAP | IS_DOT_ETH;
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
        uint32 lockedFuses = CANNOT_UNWRAP | IS_DOT_ETH;
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
        address actualSubregistry = address(registry.getSubregistry(testLabel));
        assertTrue(actualSubregistry != address(0), "Subregistry should be created");
        
        // Verify it's a proxy pointing to our implementation
        // The factory creates a proxy, so we can verify it's pointing to the right implementation
        MigratedWrappedNameRegistry migratedRegistry = MigratedWrappedNameRegistry(actualSubregistry);
        assertEq(address(migratedRegistry.universalResolver()), address(universalResolver), "Should have correct universal resolver");
    }

    // Comprehensive fuse→role mapping tests

    function test_fuse_role_mapping_no_fuses_burnt() public {
        // Setup locked name with only CANNOT_UNWRAP (no other fuses burnt)
        uint32 lockedFuses = CANNOT_UNWRAP | IS_DOT_ETH;
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));
        
        // Prepare migration data - incoming roleBitmap should be ignored
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                label: testLabel,
                owner: user,
                subregistry: address(0), // Will be created by factory
                resolver: address(0xABCD),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_SUBREGISTRY // This should be ignored
            }),
            toL1: true,
            dnsEncodedName: NameUtils.dnsEncodeEthLabel("test"),
            salt: abi.encodePacked(testLabel, block.timestamp)
        });
        
        bytes memory data = abi.encode(migrationData);
        
        // Call onERC1155Received
        vm.prank(address(nameWrapper));
        controller.onERC1155Received(owner, owner, testTokenId, 1, data);
        
        // Get the registered name and check roles
        (uint256 registeredTokenId,,) = registry.getNameData(testLabel);
        uint256 resource = registry.testGetResourceFromTokenId(registeredTokenId);
        uint256 userRoles = registry.roles(resource, user);
        
        // Since no additional fuses are burnt, user should get renew and resolver roles (but never registrar)
        assertTrue((userRoles & LibRegistryRoles.ROLE_RENEW) != 0, "Should have ROLE_RENEW");
        assertTrue((userRoles & LibRegistryRoles.ROLE_RENEW_ADMIN) != 0, "Should have ROLE_RENEW_ADMIN");
        assertTrue((userRoles & LibRegistryRoles.ROLE_SET_RESOLVER) != 0, "Should have ROLE_SET_RESOLVER");
        assertTrue((userRoles & LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN) != 0, "Should have ROLE_SET_RESOLVER_ADMIN");
        
        // Users never get registrar roles regardless of fuses
        assertTrue((userRoles & LibRegistryRoles.ROLE_REGISTRAR) == 0, "Should NOT have ROLE_REGISTRAR");
        assertTrue((userRoles & LibRegistryRoles.ROLE_REGISTRAR_ADMIN) == 0, "Should NOT have ROLE_REGISTRAR_ADMIN");
        
        // Verify incoming roleBitmap was ignored
        assertTrue((userRoles & LibRegistryRoles.ROLE_SET_SUBREGISTRY) == 0, "Should NOT have ROLE_SET_SUBREGISTRY from incoming data");
    }

    function test_fuse_role_mapping_resolver_fuse_burnt() public {
        // Setup locked name with CANNOT_SET_RESOLVER already burnt
        uint32 lockedFuses = CANNOT_UNWRAP | CANNOT_SET_RESOLVER | IS_DOT_ETH;
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));
        
        // Prepare migration data
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                label: testLabel,
                owner: user,
                subregistry: address(0), // Will be created by factory
                resolver: address(0xABCD),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN // Should be ignored
            }),
            toL1: true,
            dnsEncodedName: NameUtils.dnsEncodeEthLabel("test"),
            salt: abi.encodePacked(testLabel, block.timestamp)
        });
        
        bytes memory data = abi.encode(migrationData);
        
        // Call onERC1155Received
        vm.prank(address(nameWrapper));
        controller.onERC1155Received(owner, owner, testTokenId, 1, data);
        
        // Get the registered name and check roles
        (uint256 registeredTokenId,,) = registry.getNameData(testLabel);
        uint256 resource = registry.testGetResourceFromTokenId(registeredTokenId);
        uint256 userRoles = registry.roles(resource, user);
        
        // Should still have base roles but never registrar roles
        assertTrue((userRoles & LibRegistryRoles.ROLE_RENEW) != 0, "Should have ROLE_RENEW");
        assertTrue((userRoles & LibRegistryRoles.ROLE_RENEW_ADMIN) != 0, "Should have ROLE_RENEW_ADMIN");
        
        // Users never get registrar roles
        assertTrue((userRoles & LibRegistryRoles.ROLE_REGISTRAR) == 0, "Should NOT have ROLE_REGISTRAR");
        assertTrue((userRoles & LibRegistryRoles.ROLE_REGISTRAR_ADMIN) == 0, "Should NOT have ROLE_REGISTRAR_ADMIN");
        
        // Should NOT have resolver roles since CANNOT_SET_RESOLVER is burnt
        assertTrue((userRoles & LibRegistryRoles.ROLE_SET_RESOLVER) == 0, "Should NOT have ROLE_SET_RESOLVER");
        assertTrue((userRoles & LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN) == 0, "Should NOT have ROLE_SET_RESOLVER_ADMIN");
    }


    function test_fuses_burnt_after_migration_completes() public {
        // Setup locked name (CANNOT_BURN_FUSES not set so migration can proceed)
        uint32 initialFuses = CANNOT_UNWRAP | IS_DOT_ETH;
        nameWrapper.setFuseData(testTokenId, initialFuses, uint64(block.timestamp + 86400));
        
        // Prepare migration data
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                label: testLabel,
                owner: user,
                subregistry: address(0), // Will be created by factory
                resolver: address(0xABCD),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_SUBREGISTRY // Should be ignored
            }),
            toL1: true,
            dnsEncodedName: NameUtils.dnsEncodeEthLabel("test"),
            salt: abi.encodePacked(testLabel, block.timestamp)
        });
        
        bytes memory data = abi.encode(migrationData);
        
        // Call onERC1155Received
        vm.prank(address(nameWrapper));
        controller.onERC1155Received(owner, owner, testTokenId, 1, data);
        
        // Verify that ALL required fuses are now burnt (migration completed, then fuses burnt)
        (, uint32 finalFuses, ) = nameWrapper.getData(testTokenId);
        
        // Check that all required fuses are burnt
        assertTrue((finalFuses & CANNOT_UNWRAP) != 0, "CANNOT_UNWRAP should remain burnt");
        assertTrue((finalFuses & CANNOT_BURN_FUSES) != 0, "CANNOT_BURN_FUSES should be burnt after migration");
        assertTrue((finalFuses & CANNOT_TRANSFER) != 0, "CANNOT_TRANSFER should be burnt after migration");
        assertTrue((finalFuses & CANNOT_SET_RESOLVER) != 0, "CANNOT_SET_RESOLVER should be burnt after migration");
        assertTrue((finalFuses & CANNOT_SET_TTL) != 0, "CANNOT_SET_TTL should be burnt after migration");
        assertTrue((finalFuses & CANNOT_CREATE_SUBDOMAIN) != 0, "CANNOT_CREATE_SUBDOMAIN should be burnt after migration");
        assertTrue((finalFuses & CANNOT_APPROVE) != 0, "CANNOT_APPROVE should be burnt after migration");
        
        // Verify name was successfully migrated despite all fuses being burnt after
        (uint256 registeredTokenId,,) = registry.getNameData(testLabel);
        assertTrue(registeredTokenId != 0, "Name should be successfully registered");
    }

    function test_Revert_invalid_non_eth_name() public {
        // Setup locked name without IS_DOT_ETH fuse (not a .eth domain)
        uint32 lockedFuses = CANNOT_UNWRAP; // Missing IS_DOT_ETH
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));
        
        // Prepare migration data
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                label: testLabel,
                owner: user,
                subregistry: address(0), // Will be created by factory
                resolver: address(0xABCD),
                expires: uint64(block.timestamp + 86400),
                roleBitmap: LibRegistryRoles.ROLE_SET_SUBREGISTRY
            }),
            toL1: true,
            dnsEncodedName: NameUtils.dnsEncodeEthLabel("test"),
            salt: abi.encodePacked(testLabel, block.timestamp)
        });
        
        bytes memory data = abi.encode(migrationData);
        
        // Should revert because IS_DOT_ETH fuse is not set
        vm.expectRevert(abi.encodeWithSelector(L1LockedMigrationController.NotDotEthName.selector, testTokenId));
        vm.prank(address(nameWrapper));
        controller.onERC1155Received(owner, owner, testTokenId, 1, data);
    }


}