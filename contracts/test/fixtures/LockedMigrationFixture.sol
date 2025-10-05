// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// import {VerifiableFactory} from "../../lib/verifiable-factory/src/VerifiableFactory.sol";
// import {MockL1Bridge} from "../../src/mocks/MockL1Bridge.sol";
// import {LibBridgeRoles} from "../../src/common/IBridge.sol";
// import {LibRegistryRoles} from "../../src/common/LibRegistryRoles.sol";
// import {L1BridgeController} from "../../src/L1/L1BridgeController.sol";
// import {LockedMigrationController} from "../../src/L1/LockedMigrationController.sol";
// import {MigratedWrapperRegistry} from "../../src/L1/MigratedWrapperRegistry.sol";
// import {NameWrapperFixture} from "./NameWrapperFixture.sol";
// import {ETHRegistryMixin} from "./ETHRegistryMixin.sol";

// contract LockedMigrationFixture is NameWrapperFixture, ETHRegistryMixin {
//     MockL1Bridge bridge;
//     L1BridgeController bridgeController;
//     LockedMigrationController migrationController;

//     VerifiableFactory migratedRegistryFactory;
//     MigratedWrapperRegistry migratedRegistryImpl;

//     function deployLockedMigration() internal {
//         bridge = new MockL1Bridge();

//         migratedRegistryFactory = new VerifiableFactory();
//         migratedRegistryImpl = new MigratedWrapperRegistry(
//             nameWrapper,
//             ethRegistry,
//             migratedRegistryFactory,
//             datastore,
//             metadata
//         );

//         bridgeController = new L1BridgeController(ethRegistry, bridge);

//         ethRegistry.grantRootRoles(
//             LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_BURN,
//             address(bridgeController)
//         );
//         bridgeController.grantRootRoles(LibBridgeRoles.ROLE_EJECTOR, address(migrationController));

//         migrationController = new LockedMigrationController(
//             nameWrapper,
//             bridgeController,
//             migratedRegistryFactory,
//             address(migratedRegistryImpl)
//         );
//         bridgeController.grantRootRoles(LibBridgeRoles.ROLE_EJECTOR, address(migrationController));
//     }

//     function createLockedMigrationData(
//         bytes memory name
//     ) internal view returns (LockedMigrationController.Data memory) {
//         return
//             LockedMigrationController.Data({
//                 id: uint256(NameCoder.namehash(name, 0)),
//                 owner: user,
//                 resolver: address(1),
//                 salt: uint256(keccak256(abi.encodePacked(name, block.timestamp)))
//             });
//     }
// }
