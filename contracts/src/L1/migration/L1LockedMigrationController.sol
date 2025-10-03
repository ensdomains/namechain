// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {INameWrapper, CAN_EXTEND_EXPIRY} from "@ens/contracts/wrapper/INameWrapper.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {IBridge} from "../../common/bridge/interfaces/IBridge.sol";
import {MigrationData} from "../../common/bridge/types/TransferData.sol";
import {UnauthorizedCaller} from "../../common/CommonErrors.sol";
import {LibLabel} from "../../common/utils/LibLabel.sol";
import {L1BridgeController} from "../bridge/L1BridgeController.sol";

import {LockedNamesLib} from "./libraries/LockedNamesLib.sol";

contract L1LockedMigrationController is IERC1155Receiver, ERC165, Ownable {
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    IBaseRegistrar public immutable ETH_REGISTRY_V1;

    INameWrapper public immutable NAME_WRAPPER;

    IBridge public immutable BRIDGE;

    L1BridgeController public immutable L1_BRIDGE_CONTROLLER;

    VerifiableFactory public immutable FACTORY;

    address public immutable MIGRATED_REGISTRY_IMPLEMENTATION;

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    error TokenIdMismatch(uint256 tokenId, uint256 expectedTokenId);

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        IBaseRegistrar ethRegistryV1_,
        INameWrapper nameWrapper_,
        IBridge bridge_,
        L1BridgeController l1BridgeController_,
        VerifiableFactory factory_,
        address migratedRegistryImplementation_
    ) Ownable(msg.sender) {
        ETH_REGISTRY_V1 = ethRegistryV1_;
        NAME_WRAPPER = nameWrapper_;
        BRIDGE = bridge_;
        L1_BRIDGE_CONTROLLER = l1BridgeController_;
        FACTORY = factory_;
        MIGRATED_REGISTRY_IMPLEMENTATION = migratedRegistryImplementation_;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    function onERC1155Received(
        address /*operator*/,
        address /*from*/,
        uint256 tokenId,
        uint256 /*amount*/,
        bytes calldata data
    ) external virtual returns (bytes4) {
        if (msg.sender != address(NAME_WRAPPER)) {
            revert UnauthorizedCaller(msg.sender);
        }

        (MigrationData memory migrationData) = abi.decode(data, (MigrationData));
        MigrationData[] memory migrationDataArray = new MigrationData[](1);
        migrationDataArray[0] = migrationData;

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        _migrateLockedEthNames(tokenIds, migrationDataArray);

        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address /*operator*/,
        address /*from*/,
        uint256[] memory tokenIds,
        uint256[] memory /*amounts*/,
        bytes calldata data
    ) external virtual returns (bytes4) {
        if (msg.sender != address(NAME_WRAPPER)) {
            revert UnauthorizedCaller(msg.sender);
        }

        (MigrationData[] memory migrationDataArray) = abi.decode(data, (MigrationData[]));

        _migrateLockedEthNames(tokenIds, migrationDataArray);

        return this.onERC1155BatchReceived.selector;
    }

    function _migrateLockedEthNames(
        uint256[] memory tokenIds,
        MigrationData[] memory migrationDataArray
    ) internal {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            (, uint32 fuses, ) = NAME_WRAPPER.getData(tokenIds[i]);

            // Validate fuses and name type
            LockedNamesLib.validateLockedName(fuses, tokenIds[i]);
            LockedNamesLib.validateIsDotEth2LD(fuses, tokenIds[i]);

            // Determine permissions from name configuration (mask out CAN_EXTEND_EXPIRY to prevent automatic renewal for 2LDs)
            uint32 adjustedFuses = fuses & ~CAN_EXTEND_EXPIRY;
            (uint256 tokenRoles, uint256 subRegistryRoles) = LockedNamesLib
                .generateRoleBitmapsFromFuses(adjustedFuses);

            // Create new registry instance for the migrated name
            address subregistry = LockedNamesLib.deployMigratedRegistry(
                FACTORY,
                MIGRATED_REGISTRY_IMPLEMENTATION,
                migrationDataArray[i].transferData.owner,
                subRegistryRoles,
                migrationDataArray[i].salt,
                migrationDataArray[i].transferData.dnsEncodedName
            );

            // Configure transfer data with registry and permission details
            migrationDataArray[i].transferData.subregistry = subregistry;
            migrationDataArray[i].transferData.roleBitmap = tokenRoles;

            // Ensure name data consistency for migration
            string memory label = LibLabel.extractLabel(
                migrationDataArray[i].transferData.dnsEncodedName
            );
            uint256 expectedTokenId = uint256(keccak256(bytes(label)));
            if (tokenIds[i] != expectedTokenId) {
                revert TokenIdMismatch(tokenIds[i], expectedTokenId);
            }

            // Process the locked name migration through bridge
            L1_BRIDGE_CONTROLLER.completeEjectionToL1(migrationDataArray[i].transferData);

            // Finalize migration by freezing the name
            LockedNamesLib.freezeName(NAME_WRAPPER, tokenIds[i], fuses);
        }
    }
}
