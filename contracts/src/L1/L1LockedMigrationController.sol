// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {INameWrapper} from "@ens/contracts/wrapper/INameWrapper.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {TransferData, MigrationData} from "../common/TransferData.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBridge} from "../common/IBridge.sol";
import {BridgeEncoder} from "../common/BridgeEncoder.sol";
import {L1BridgeController} from "./L1BridgeController.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {MigratedWrappedNameRegistry} from "./MigratedWrappedNameRegistry.sol";
import {LibRegistryRoles} from "../common/LibRegistryRoles.sol";
import {LibLockedNames} from "./LibLockedNames.sol";
import {VerifiableFactory} from "../../lib/verifiable-factory/src/VerifiableFactory.sol";
import {IRegistryDatastore} from "../common/IRegistryDatastore.sol";
import {IRegistryMetadata} from "../common/IRegistryMetadata.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";

contract L1LockedMigrationController is IERC1155Receiver, ERC165, Ownable {
    error UnauthorizedCaller(address caller);   
    error MigrationFailed();
    error TokenIdMismatch(uint256 tokenId, uint256 expectedTokenId);

    IBaseRegistrar public immutable ethRegistryV1;
    INameWrapper public immutable nameWrapper;
    IBridge public immutable bridge;
    L1BridgeController public immutable l1BridgeController;
    VerifiableFactory public immutable factory;
    address public immutable migratedRegistryImplementation;
    IRegistryDatastore public immutable datastore;
    IRegistryMetadata public immutable metadata;
    IUniversalResolver public immutable universalResolver;

    constructor(
        IBaseRegistrar _ethRegistryV1, 
        INameWrapper _nameWrapper, 
        IBridge _bridge, 
        L1BridgeController _l1BridgeController,
        VerifiableFactory _factory,
        address _migratedRegistryImplementation,
        IRegistryDatastore _datastore,
        IRegistryMetadata _metadata,
        IUniversalResolver _universalResolver
    ) Ownable(msg.sender) {
        ethRegistryV1 = _ethRegistryV1;
        nameWrapper = _nameWrapper;
        bridge = _bridge;
        l1BridgeController = _l1BridgeController;
        factory = _factory;
        migratedRegistryImplementation = _migratedRegistryImplementation;
        datastore = _datastore;
        metadata = _metadata;
        universalResolver = _universalResolver;
    }

    function supportsInterface(bytes4 interfaceId) public virtual view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function onERC1155Received(address /*operator*/, address /*from*/, uint256 tokenId, uint256 /*amount*/, bytes calldata data) external virtual returns (bytes4) {
        if (msg.sender != address(nameWrapper)) {
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

    function onERC1155BatchReceived(address /*operator*/, address /*from*/, uint256[] memory tokenIds, uint256[] memory /*amounts*/, bytes calldata data) external virtual returns (bytes4) {
        if (msg.sender != address(nameWrapper)) {
            revert UnauthorizedCaller(msg.sender);
        }

        (MigrationData[] memory migrationDataArray) = abi.decode(data, (MigrationData[]));

        _migrateLockedEthNames(tokenIds, migrationDataArray);

        return this.onERC1155BatchReceived.selector;
    }

    function _migrateLockedEthNames(uint256[] memory tokenIds, MigrationData[] memory migrationDataArray) internal {                
        for (uint256 i = 0; i < tokenIds.length; i++) {
            (, uint32 fuses, ) = nameWrapper.getData(tokenIds[i]);
            
            // Validate fuses and name type
            LibLockedNames.validateLockedName(fuses, tokenIds[i]);
            LibLockedNames.validateIsDotEth2LD(fuses, tokenIds[i]);
            
            // Deploy MigratedWrappedNameRegistry with transferData.owner as owner
            uint256 salt = uint256(keccak256(migrationDataArray[i].salt));
            address subregistry = LibLockedNames.deployMigratedRegistry(
                factory,
                migratedRegistryImplementation,
                migrationDataArray[i].transferData.owner,
                salt
            );
            
            // Update transferData with the new subregistry and generated role bitmap
            migrationDataArray[i].transferData.subregistry = subregistry;
            migrationDataArray[i].transferData.roleBitmap = LibLockedNames.generateRoleBitmapFromFuses(fuses, false);
            
            // Validate that tokenId matches the label hash
            uint256 expectedTokenId = uint256(keccak256(bytes(migrationDataArray[i].transferData.label)));
            if (tokenIds[i] != expectedTokenId) {
                revert TokenIdMismatch(tokenIds[i], expectedTokenId);
            }
            
            // Migrate locked name using the DNS-encoded name for hierarchy traversal
            l1BridgeController.handleLockedNameMigration(migrationDataArray[i].transferData);

            // Burn all migration fuses
            LibLockedNames.burnAllMigrationFuses(nameWrapper, tokenIds[i]);
        }
    }
}