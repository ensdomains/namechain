// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering

import {Test, Vm} from "forge-std/Test.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

import {EACBaseRolesLib} from "~src/common/access-control/EnhancedAccessControl.sol";
import {IBridge} from "~src/common/bridge/interfaces/IBridge.sol";
import {BridgeRolesLib} from "~src/common/bridge/libraries/BridgeRolesLib.sol";
import {TransferData} from "~src/common/bridge/types/TransferData.sol";
import {IRegistryMetadata} from "~src/common/registry/interfaces/IRegistryMetadata.sol";
import {PermissionedRegistry} from "~src/common/registry/PermissionedRegistry.sol";
import {RegistryDatastore} from "~src/common/registry/RegistryDatastore.sol";
import {RegistryRolesLib} from "~src/common/registry/libraries/RegistryRolesLib.sol";
import {LibLabel} from "~src/common/utils/LibLabel.sol";
import {L1BridgeController} from "~src/L1/bridge/L1BridgeController.sol";

contract MockRegistryMetadata is IRegistryMetadata {
    function tokenUri(uint256) external pure override returns (string memory) {
        return "";
    }
}

contract MockBridge is IBridge {
    bytes public lastMessage;

    function sendMessage(bytes memory message) external payable override {
        lastMessage = message;
    }

    function getMinGasLimit(bytes calldata) external pure override returns (uint32) {
        return 100000;
    }
}

contract BridgeControllerSetBridgeTest is Test {
    RegistryDatastore datastore;
    MockRegistryMetadata registryMetadata;
    PermissionedRegistry registry;
    L1BridgeController bridgeController;
    MockBridge bridge1;
    MockBridge bridge2;

    address user1 = address(0x1);
    address user2 = address(0x2);

    function setUp() public {
        datastore = new RegistryDatastore();
        registryMetadata = new MockRegistryMetadata();
        bridge1 = new MockBridge();

        registry = new PermissionedRegistry(
            datastore,
            registryMetadata,
            address(this),
            EACBaseRolesLib.ALL_ROLES
        );

        bridgeController = new L1BridgeController(registry, bridge1);

        registry.grantRootRoles(
            RegistryRolesLib.ROLE_REGISTRAR | RegistryRolesLib.ROLE_RENEW,
            address(this)
        );
        registry.grantRootRoles(
            RegistryRolesLib.ROLE_REGISTRAR |
                RegistryRolesLib.ROLE_RENEW |
                RegistryRolesLib.ROLE_BURN,
            address(bridgeController)
        );

        bridgeController.grantRootRoles(BridgeRolesLib.ROLE_EJECTOR, address(bridge1));
    }

    ////////////////////////////////////////////////////////////////////////
    // setBridge Tests
    ////////////////////////////////////////////////////////////////////////

    function test_setBridge_success() public {
        bridge2 = new MockBridge();

        // Grant ROLE_SET_BRIDGE to test address
        bridgeController.grantRootRoles(BridgeRolesLib.ROLE_SET_BRIDGE, address(this));

        // Verify initial bridge
        assertEq(address(bridgeController.BRIDGE()), address(bridge1));

        vm.recordLogs();
        bridgeController.setBridge(bridge2);

        // Verify bridge was updated
        assertEq(address(bridgeController.BRIDGE()), address(bridge2));

        // Verify event emission
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("BridgeUpdated(address,address)")) {
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "BridgeUpdated event not emitted");
    }

    function test_setBridge_unauthorized_reverts() public {
        bridge2 = new MockBridge();

        // Try to set bridge without permission
        vm.expectRevert();
        vm.prank(user1);
        bridgeController.setBridge(bridge2);
    }

    function test_setBridge_cannot_set_zero_address() public {
        // Grant ROLE_SET_BRIDGE to test address
        bridgeController.grantRootRoles(BridgeRolesLib.ROLE_SET_BRIDGE, address(this));

        vm.expectRevert();
        bridgeController.setBridge(IBridge(address(0)));
    }


    function test_setBridge_admin_role_can_grant_permission() public {
        bridge2 = new MockBridge();

        // deployer (this contract) should have ROLE_SET_BRIDGE_ADMIN
        // Grant ROLE_SET_BRIDGE to user1
        bridgeController.grantRootRoles(BridgeRolesLib.ROLE_SET_BRIDGE, user1);

        // user1 should now be able to set bridge
        vm.prank(user1);
        bridgeController.setBridge(bridge2);

        assertEq(address(bridgeController.BRIDGE()), address(bridge2));
    }

    function test_setBridge_multiple_times() public {
        bridge2 = new MockBridge();
        MockBridge bridge3 = new MockBridge();

        // Grant ROLE_SET_BRIDGE to test address
        bridgeController.grantRootRoles(BridgeRolesLib.ROLE_SET_BRIDGE, address(this));

        // First swap
        bridgeController.setBridge(bridge2);
        assertEq(address(bridgeController.BRIDGE()), address(bridge2));

        // Second swap
        bridgeController.setBridge(bridge3);
        assertEq(address(bridgeController.BRIDGE()), address(bridge3));

        // Third swap back to original
        bridgeController.setBridge(bridge1);
        assertEq(address(bridgeController.BRIDGE()), address(bridge1));
    }

    function test_setBridge_event_contains_correct_addresses() public {
        bridge2 = new MockBridge();

        // Grant ROLE_SET_BRIDGE to test address
        bridgeController.grantRootRoles(BridgeRolesLib.ROLE_SET_BRIDGE, address(this));

        address oldBridge = address(bridgeController.BRIDGE());

        vm.recordLogs();
        bridgeController.setBridge(bridge2);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Find the BridgeUpdated event and verify addresses
        bool foundEvent = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("BridgeUpdated(address,address)")) {
                foundEvent = true;
                // topics[1] should be oldBridge, topics[2] should be newBridge
                address emittedOld = address(uint160(uint256(logs[i].topics[1])));
                address emittedNew = address(uint160(uint256(logs[i].topics[2])));
                assertEq(emittedOld, oldBridge, "Event old bridge mismatch");
                assertEq(emittedNew, address(bridge2), "Event new bridge mismatch");
                break;
            }
        }
        assertTrue(foundEvent, "BridgeUpdated event not found");
    }
}
