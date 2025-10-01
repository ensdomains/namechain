// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {INameWrapper, CAN_EXTEND_EXPIRY} from "@ens/contracts/wrapper/INameWrapper.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {TransferData, MigrationData} from "../common/TransferData.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBridge} from "../common/IBridge.sol";
import {BridgeEncoder} from "../common/BridgeEncoder.sol";
import {L1BridgeController} from "./L1BridgeController.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {MigratedWrappedNameRegistry} from "./MigratedWrappedNameRegistry.sol";
import {LibRegistryRoles} from "../common/LibRegistryRoles.sol";
import {LibLockedNames} from "./LibLockedNames.sol";
import {VerifiableFactory} from "../../lib/verifiable-factory/src/VerifiableFactory.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";
import "../common/Errors.sol";

contract L1LockedMigrationController is IERC1155Receiver, ERC165, Ownable {
    error TokenIdMismatch(uint256 tokenId, uint256 expectedTokenId);

    IBaseRegistrar public immutable ethRegistryV1;
    INameWrapper public immutable nameWrapper;
    IBridge public immutable bridge;
    L1BridgeController public immutable l1BridgeController;
    VerifiableFactory public immutable factory;
    address public immutable migratedRegistryImplementation;

    constructor(
        IBaseRegistrar _ethRegistryV1,
        INameWrapper _nameWrapper,
        L1BridgeController _l1BridgeController,
        VerifiableFactory _factory,
        address _migratedRegistryImplementation
    ) Ownable(msg.sender) {
        ethRegistryV1 = _ethRegistryV1;
        nameWrapper = _nameWrapper;
        bridge = _l1BridgeController.bridge();
        l1BridgeController = _l1BridgeController;
        factory = _factory;
        migratedRegistryImplementation = _migratedRegistryImplementation;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function onERC1155Received(
        address /*operator*/,
        address /*from*/,
        uint256 tokenId,
        uint256 /*amount*/,
        bytes calldata data
    ) external virtual returns (bytes4) {
        if (msg.sender != address(nameWrapper)) {
            revert UnauthorizedCaller(msg.sender);
        }

        MigrationData memory migrationData = abi.decode(data, (MigrationData));
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
        if (msg.sender != address(nameWrapper)) {
            revert UnauthorizedCaller(msg.sender);
        }

        MigrationData[] memory migrationDataArray = abi.decode(
            data,
            (MigrationData[])
        );

        _migrateLockedEthNames(tokenIds, migrationDataArray);

        return this.onERC1155BatchReceived.selector;
    }

    function _migrateLockedEthNames(
        uint256[] memory tokenIds,
        MigrationData[] memory migrationDataArray
    ) internal {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            // Ensure name data consistency for migration
            TransferData memory td = migrationDataArray[i].transferData;
            uint256 wrappedTokenId = uint256(
                NameCoder.namehash(td.dnsEncodedName, 0)
            );
            if (tokenIds[i] != wrappedTokenId) {
                revert TokenIdMismatch(tokenIds[i], wrappedTokenId);
            }

            (, uint32 fuses, ) = nameWrapper.getData(wrappedTokenId);

            // Validate fuses and name type
            LibLockedNames.validateLockedName(fuses, wrappedTokenId);
            LibLockedNames.validateIsDotEth2LD(fuses, wrappedTokenId);

            // Determine permissions from name configuration (mask out CAN_EXTEND_EXPIRY to prevent automatic renewal for 2LDs)
            uint32 adjustedFuses = fuses & ~CAN_EXTEND_EXPIRY;
            (uint256 tokenRoles, uint256 subRegistryRoles) = LibLockedNames
                .generateRoleBitmapsFromFuses(adjustedFuses);

            // Create new registry instance for the migrated name
            address subregistry = LibLockedNames.deployMigratedRegistry(
                factory,
                migratedRegistryImplementation,
                td.owner,
                subRegistryRoles,
                migrationDataArray[i].salt,
                td.dnsEncodedName
            );

            // Configure transfer data with registry and permission details
            td.subregistry = subregistry;
            td.roleBitmap = tokenRoles;

            // Process the locked name migration through bridge
            l1BridgeController.completeEjectionToL1(td);

            // Finalize migration by freezing the name
            LibLockedNames.freezeName(nameWrapper, wrappedTokenId, fuses);
        }
    }
}
