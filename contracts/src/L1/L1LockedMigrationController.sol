// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {INameWrapper, CANNOT_UNWRAP, CANNOT_BURN_FUSES, CANNOT_TRANSFER, CANNOT_SET_RESOLVER, CANNOT_SET_TTL, CANNOT_CREATE_SUBDOMAIN, CANNOT_APPROVE} from "@ens/contracts/wrapper/INameWrapper.sol";
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
import {VerifiableFactory} from "../../lib/verifiable-factory/src/VerifiableFactory.sol";
import {IRegistryDatastore} from "../common/IRegistryDatastore.sol";
import {IRegistryMetadata} from "../common/IRegistryMetadata.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";

contract L1LockedMigrationController is IERC1155Receiver, ERC165, Ownable {
    error UnauthorizedCaller(address caller);   
    error MigrationFailed();
    error TokenIdMismatch(uint256 tokenId, uint256 expectedTokenId);
    error InconsistentFusesState();
    error NameNotLocked();

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
            
            // Check if name is locked
            if (fuses & CANNOT_UNWRAP == 0) {
                revert NameNotLocked();
            }
            
            // Cannot migrate if CANNOT_BURN_FUSES is already burnt
            if ((fuses & CANNOT_BURN_FUSES) != 0) {
                revert InconsistentFusesState();
            }
            
            // Create MigratedWrappedNameRegistry using factory with salt
            uint256 salt = uint256(keccak256(migrationDataArray[i].salt));
            bytes memory initData = abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                datastore,
                metadata,
                address(this),
                LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_REGISTRAR_ADMIN,
                universalResolver
            );
            address subregistry = factory.deployProxy(migratedRegistryImplementation, salt, initData);
            
            // Grant L1BridgeController REGISTRAR role on the new subregistry for subdomain migrations
            IPermissionedRegistry(subregistry).grantRootRoles(
                LibRegistryRoles.ROLE_REGISTRAR, 
                address(l1BridgeController)
            );
            
            // Update transferData with the new subregistry
            TransferData memory transferData = migrationDataArray[i].transferData;
            transferData.subregistry = subregistry;
            
            // setup roles
            transferData.roleBitmap = 
                LibRegistryRoles.ROLE_RENEW | LibRegistryRoles.ROLE_RENEW_ADMIN;
            // setting resolver ability
            if (fuses & CANNOT_SET_RESOLVER == 0) {
                transferData.roleBitmap = transferData.roleBitmap | LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN;
            }            
            // registering subdomains
            if (fuses & CANNOT_CREATE_SUBDOMAIN == 0) {
                transferData.roleBitmap = transferData.roleBitmap | LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_REGISTRAR_ADMIN;
            }
            
            // Validate that tokenId matches the label hash
            uint256 expectedTokenId = uint256(keccak256(bytes(transferData.label)));
            if (tokenIds[i] != expectedTokenId) {
                revert TokenIdMismatch(tokenIds[i], expectedTokenId);
            }
            
            // Migrate locked name using the DNS-encoded name for hierarchy traversal
            l1BridgeController.handleLockedNameMigration(transferData);

            // Burn all required fuses: CANNOT_BURN_FUSES, CANNOT_TRANSFER, 
            // CANNOT_SET_RESOLVER, CANNOT_SET_TTL, CANNOT_CREATE_SUBDOMAIN, CANNOT_APPROVE
            //
            // NOTE: CANNOT_UNWRAP is already burnt
            uint16 fusesToBurn = uint16(
                CANNOT_BURN_FUSES | 
                CANNOT_TRANSFER | 
                CANNOT_SET_RESOLVER | 
                CANNOT_SET_TTL | 
                CANNOT_CREATE_SUBDOMAIN | 
                CANNOT_APPROVE
            );
            nameWrapper.setFuses(bytes32(tokenIds[i]), fusesToBurn);            
        }
    }
}