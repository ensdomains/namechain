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
import {RegistryRolesLib} from "~src/common/registry/libraries/RegistryRolesLib.sol";
import {PermissionedRegistry} from "~src/common/registry/PermissionedRegistry.sol";
import {RegistryDatastore} from "~src/common/registry/RegistryDatastore.sol";
import {SimpleRegistryMetadata} from "~src/common/registry/SimpleRegistryMetadata.sol";
import {L1BridgeController} from "~src/L1/bridge/L1BridgeController.sol";
import {L2BridgeController} from "~src/L2/bridge/L2BridgeController.sol";
import {ISurgeNativeBridge} from "~src/common/bridge/interfaces/ISurgeNativeBridge.sol";
import {L1SurgeBridge} from "~src/L1/bridge/L1SurgeBridge.sol";
import {L2SurgeBridge} from "~src/L2/bridge/L2SurgeBridge.sol";
import {MockHCAFactoryBasic} from "~test/mocks/MockHCAFactoryBasic.sol";
import {MockSurgeNativeBridge} from "~test/mocks/MockSurgeNativeBridge.sol";

contract BridgeTest is Test {
    RegistryDatastore datastore;
    MockHCAFactoryBasic hcaFactory;

    PermissionedRegistry l1Registry;
    PermissionedRegistry l2Registry;
    MockSurgeNativeBridge surgeNativeBridge;
    L1SurgeBridge l1SurgeBridge;
    L2SurgeBridge l2SurgeBridge;
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
        hcaFactory = new MockHCAFactoryBasic();
        SimpleRegistryMetadata metadata = new SimpleRegistryMetadata(hcaFactory);
        l1Registry = new PermissionedRegistry(
            datastore,
            hcaFactory,
            metadata,
            address(this),
            EACBaseRolesLib.ALL_ROLES
        );
        l2Registry = new PermissionedRegistry(
            datastore,
            hcaFactory,
            metadata,
            address(this),
            EACBaseRolesLib.ALL_ROLES
        );

        // Deploy Surge bridge mock
        surgeNativeBridge = new MockSurgeNativeBridge();

        // Deploy placeholder bridges first (needed to create controllers)
        l1SurgeBridge = new L1SurgeBridge(surgeNativeBridge, L1_CHAIN_ID, L2_CHAIN_ID, L1BridgeController(address(0)));
        l2SurgeBridge = new L2SurgeBridge(surgeNativeBridge, L2_CHAIN_ID, L1_CHAIN_ID, L2BridgeController(address(0)));

        // Deploy controllers with initial bridges
        l1Controller = new L1BridgeController(l1Registry, l1SurgeBridge);
        l2Controller = new L2BridgeController(l2SurgeBridge, l2Registry, datastore);

        // Re-deploy bridges with correct controller references
        l1SurgeBridge = new L1SurgeBridge(surgeNativeBridge, L1_CHAIN_ID, L2_CHAIN_ID, l1Controller);
        l2SurgeBridge = new L2SurgeBridge(surgeNativeBridge, L2_CHAIN_ID, L1_CHAIN_ID, l2Controller);

        // Set up bridges with destination addresses
        l1SurgeBridge.setDestBridgeAddress(address(l2SurgeBridge));
        l2SurgeBridge.setDestBridgeAddress(address(l1SurgeBridge));

        // Grant necessary roles to controllers
        l1Registry.grantRootRoles(
            RegistryRolesLib.ROLE_REGISTRAR |
                RegistryRolesLib.ROLE_RENEW |
                RegistryRolesLib.ROLE_UNREGISTER,
            address(l1Controller)
        );
        l2Registry.grantRootRoles(
            RegistryRolesLib.ROLE_REGISTRAR | RegistryRolesLib.ROLE_RENEW,
            address(l2Controller)
        );

        // Update controller bridge references
        l1Controller.grantRootRoles(BridgeRolesLib.ROLE_SET_BRIDGE, address(this));
        l2Controller.grantRootRoles(BridgeRolesLib.ROLE_SET_BRIDGE, address(this));
        l1Controller.setBridge(l1SurgeBridge);
        l2Controller.setBridge(l2SurgeBridge);

        // Grant bridge roles so the NEW bridges can call the controllers
        l1Controller.grantRootRoles(BridgeRolesLib.ROLE_EJECTOR, address(l1SurgeBridge));
        l2Controller.grantRootRoles(BridgeRolesLib.ROLE_EJECTOR, address(l2SurgeBridge));
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
        ISurgeNativeBridge.Message memory surgeMessage = ISurgeNativeBridge.Message({
            id: 0,
            fee: 0,
            gasLimit: surgeNativeBridge.getMessageMinGasLimit(bridgeMessage.length),
            from: address(l2SurgeBridge),
            srcChainId: L2_CHAIN_ID,
            srcOwner: address(this),
            destChainId: L1_CHAIN_ID,
            destOwner: address(this),
            to: address(l1SurgeBridge),
            value: 0,
            data: bridgeMessage
        });

        // Send message through Surge bridge and deliver it
        (, ISurgeNativeBridge.Message memory sentMessage) = surgeNativeBridge.sendMessage(surgeMessage);
        surgeNativeBridge.deliverMessage(sentMessage);

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
