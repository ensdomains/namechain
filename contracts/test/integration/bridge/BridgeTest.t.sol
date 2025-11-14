// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test} from "forge-std/Test.sol";

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

import {
    EnhancedAccessControl,
    EACBaseRolesLib
} from "~src/common/access-control/EnhancedAccessControl.sol";
import {BridgeEncoderLib} from "~src/common/bridge/libraries/BridgeEncoderLib.sol";
import {BridgeRolesLib} from "~src/common/bridge/libraries/BridgeRolesLib.sol";
import {TransferData} from "~src/common/bridge/types/TransferData.sol";
import {IRegistry} from "~src/common/registry/interfaces/IRegistry.sol";
import {PermissionedRegistry} from "~src/common/registry/PermissionedRegistry.sol";
import {RegistryRolesLib} from "~src/common/registry/libraries/RegistryRolesLib.sol";
import {RegistryDatastore} from "~src/common/registry/RegistryDatastore.sol";
import {SimpleRegistryMetadata} from "~src/common/registry/SimpleRegistryMetadata.sol";
import {L1BridgeController} from "~src/L1/bridge/L1BridgeController.sol";
import {L2BridgeController} from "~src/L2/bridge/L2BridgeController.sol";
import {ISurgeBridge} from "~src/common/bridge/interfaces/ISurgeBridge.sol";
import {L1Bridge} from "~src/L1/bridge/L1Bridge.sol";
import {L2Bridge} from "~src/L2/bridge/L2Bridge.sol";
import {MockSurgeBridge} from "~test/mocks/MockSurgeBridge.sol";

contract BridgeTest is Test, EnhancedAccessControl {
    RegistryDatastore datastore;

    PermissionedRegistry l1Registry;
    PermissionedRegistry l2Registry;
    MockSurgeBridge surgeBridge;
    L1Bridge l1Bridge;
    L2Bridge l2Bridge;
    L1BridgeController l1Controller;
    L2BridgeController l2Controller;

    // Chain IDs for testing
    uint64 constant L1_CHAIN_ID = 1;
    uint64 constant L2_CHAIN_ID = 42;

    // Test accounts
    address user1 = address(0x1);
    address user2 = address(0x2);

    function setUp() public {
        // Deploy registries
        datastore = new RegistryDatastore();
        SimpleRegistryMetadata metadata = new SimpleRegistryMetadata();
        l1Registry = new PermissionedRegistry(
            datastore,
            metadata,
            address(this),
            EACBaseRolesLib.ALL_ROLES
        );
        l2Registry = new PermissionedRegistry(
            datastore,
            metadata,
            address(this),
            EACBaseRolesLib.ALL_ROLES
        );

        // Deploy Surge bridge mock
        surgeBridge = new MockSurgeBridge();

        // Deploy bridges with Surge integration (controllers will be set later)
        l1Bridge = new L1Bridge(surgeBridge, L1_CHAIN_ID, L2_CHAIN_ID, address(0));
        l2Bridge = new L2Bridge(surgeBridge, L2_CHAIN_ID, L1_CHAIN_ID, address(0));

        // Deploy controllers with initial bridges
        l1Controller = new L1BridgeController(l1Registry, l1Bridge);
        l2Controller = new L2BridgeController(l2Bridge, l2Registry, datastore);

        // Re-deploy bridges with correct controller addresses
        l1Bridge = new L1Bridge(surgeBridge, L1_CHAIN_ID, L2_CHAIN_ID, address(l1Controller));
        l2Bridge = new L2Bridge(surgeBridge, L2_CHAIN_ID, L1_CHAIN_ID, address(l2Controller));

        // Set up bridges with destination addresses
        l1Bridge.setDestBridgeAddress(address(l2Bridge));
        l2Bridge.setDestBridgeAddress(address(l1Bridge));

        // Grant necessary roles to controllers
        l1Registry.grantRootRoles(
            RegistryRolesLib.ROLE_REGISTRAR |
                RegistryRolesLib.ROLE_RENEW |
                RegistryRolesLib.ROLE_BURN,
            address(l1Controller)
        );
        l2Registry.grantRootRoles(
            RegistryRolesLib.ROLE_REGISTRAR | RegistryRolesLib.ROLE_RENEW,
            address(l2Controller)
        );

        // Update controller bridge references
        l1Controller.grantRootRoles(BridgeRolesLib.ROLE_SET_BRIDGE, address(this));
        l2Controller.grantRootRoles(BridgeRolesLib.ROLE_SET_BRIDGE, address(this));
        l1Controller.setBridge(l1Bridge);
        l2Controller.setBridge(l2Bridge);

        // Grant bridge roles so the NEW bridges can call the controllers
        l1Controller.grantRootRoles(BridgeRolesLib.ROLE_EJECTOR, address(l1Bridge));
        l2Controller.grantRootRoles(BridgeRolesLib.ROLE_EJECTOR, address(l2Bridge));
    }

    function testNameEjectionFromL2ToL1() public {
        // Register using just the label, as would be done in an .eth registry
        uint256 tokenId = l2Registry.register(
            "premiumname",
            user2,
            IRegistry(address(0x456)),
            address(0x789),
            EACBaseRolesLib.ALL_ROLES,
            uint64(block.timestamp + 365 days)
        );

        TransferData memory transferData = TransferData({
            dnsEncodedName: NameCoder.ethName("premiumname"),
            owner: user2,
            subregistry: address(0x123),
            resolver: address(0x456),
            roleBitmap: RegistryRolesLib.ROLE_RENEW,
            expires: uint64(block.timestamp + 123 days)
        });

        // Step 1: Initiate ejection on L2
        vm.startPrank(user2);
        l2Registry.safeTransferFrom(
            user2,
            address(l2Controller),
            tokenId,
            1,
            abi.encode(transferData)
        );
        vm.stopPrank();

        // Step 2: Simulate cross-chain message via Surge bridge
        bytes memory bridgeMessage = BridgeEncoderLib.encodeEjection(transferData);

        // Create Surge message to simulate L2->L1 message
        ISurgeBridge.Message memory surgeMessage = ISurgeBridge.Message({
            id: 0,
            fee: 0,
            gasLimit: surgeBridge.getMessageMinGasLimit(bridgeMessage.length),
            from: address(l2Bridge),
            srcChainId: L2_CHAIN_ID,
            srcOwner: address(this),
            destChainId: L1_CHAIN_ID,
            destOwner: address(this),
            to: address(l1Bridge),
            value: 0,
            data: bridgeMessage
        });

        // Send message through Surge bridge and deliver it
        (, ISurgeBridge.Message memory sentMessage) = surgeBridge.sendMessage(surgeMessage);
        surgeBridge.deliverMessage(sentMessage);

        // Step 3: Verify the name is registered on L1
        assertEq(l1Registry.ownerOf(tokenId), transferData.owner);
        assertEq(address(l1Registry.getSubregistry("premiumname")), transferData.subregistry);
        assertEq(l1Registry.getResolver("premiumname"), transferData.resolver);
        assertEq(l1Registry.getEntry(tokenId).expiry, transferData.expires);
        assertEq(
            l1Registry.roles(l1Registry.getResource(tokenId), transferData.owner),
            transferData.roleBitmap
        );
    }
}
