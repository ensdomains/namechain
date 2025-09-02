// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SimpleRegistryMetadata} from "../common/SimpleRegistryMetadata.sol";
import {PermissionedRegistry} from "../common/PermissionedRegistry.sol";
import {IRegistryDatastore} from "../common/IRegistryDatastore.sol";
import {IRegistryMetadata} from "../common/IRegistryMetadata.sol";
import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {INameWrapper} from "@ens/contracts/wrapper/INameWrapper.sol";
import {LibLockedNames} from "./LibLockedNames.sol";
import {ENS} from "@ens/contracts/registry/ENS.sol";
import {TransferData, MigrationData} from "../common/TransferData.sol";
import {LibRegistryRoles} from "../common/LibRegistryRoles.sol";
import {VerifiableFactory} from "../../lib/verifiable-factory/src/VerifiableFactory.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {IStandardRegistry} from "../common/IStandardRegistry.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {RegistryUtils} from "@ens/contracts/universalResolver/RegistryUtils.sol";
import "./MigrationErrors.sol";
import "../common/Errors.sol";

/**
 * @title MigratedWrappedNameRegistry
 * @dev A registry for migrated wrapped names that inherits from PermissionedRegistry and is upgradeable using the UUPS pattern.
 * This contract provides resolver fallback to the universal resolver for names that haven't been migrated yet.
 * It also handles subdomain migration by receiving NFT transfers from the NameWrapper.
 */
contract MigratedWrappedNameRegistry is Initializable, PermissionedRegistry, UUPSUpgradeable, IERC1155Receiver {
    using NameCoder for bytes;
    
    uint256 internal constant ROLE_UPGRADE = 1 << 20;
    uint256 internal constant ROLE_UPGRADE_ADMIN = ROLE_UPGRADE << 128;
    
    error NoParentDomain();
    
    bytes public parentDnsEncodedName;
    INameWrapper public immutable nameWrapper;
    ENS public immutable ensRegistry;
    VerifiableFactory public immutable factory;
    IPermissionedRegistry public immutable ethRegistry;

    constructor(
        INameWrapper _nameWrapper,
        ENS _ensRegistry,
        VerifiableFactory _factory,
        IPermissionedRegistry _ethRegistry,
        IRegistryDatastore _datastore,
        IRegistryMetadata _metadataProvider
    ) PermissionedRegistry(_datastore, _metadataProvider, _msgSender(), 0) {
        nameWrapper = _nameWrapper;
        ensRegistry = _ensRegistry;
        factory = _factory;
        ethRegistry = _ethRegistry;
        // Prevents initialization on the implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the MigratedWrappedNameRegistry contract.
     * @param _parentDnsEncodedName The DNS-encoded name of the parent domain.
     * @param _ownerAddress The address that will own this registry.
     * @param _registrarAddress Optional address to grant ROLE_REGISTRAR permissions (typically for testing).
     */
    function initialize(
        bytes calldata _parentDnsEncodedName,
        address _ownerAddress,
        address _registrarAddress
    ) public initializer {
        require(_ownerAddress != address(0), "Owner cannot be zero address");
        
        // Set the parent domain for name resolution fallback
        parentDnsEncodedName = _parentDnsEncodedName;
        
        // Configure owner with upgrade permissions
        _grantRoles(ROOT_RESOURCE, ROLE_UPGRADE | ROLE_UPGRADE_ADMIN, _ownerAddress, false);
        
        // Grant registrar role if specified (typically for testing)
        if (_registrarAddress != address(0)) {
            _grantRoles(ROOT_RESOURCE, LibRegistryRoles.ROLE_REGISTRAR, _registrarAddress, false);
        }
    }

    function getResolver(string calldata label) external view override returns (address) {
        uint256 canonicalId = NameUtils.labelToCanonicalId(label);
        (, uint64 expires, ) = datastore.getSubregistry(canonicalId);
        
        // Use fallback resolver for unregistered names
        if (expires == 0) {
            // Construct complete domain name for registry lookup
            bytes memory dnsEncodedName = abi.encodePacked(
                bytes1(uint8(bytes(label).length)),
                label,
                parentDnsEncodedName
            );
            
            // Retrieve resolver from legacy registry system
            (address resolverAddress, , ) = RegistryUtils.findResolver(ensRegistry, dnsEncodedName, 0);
            return resolverAddress;
        }
        
        // Return no resolver for expired names
        if (expires <= block.timestamp) {
            return address(0);
        }
        
        // Return the configured resolver for registered names
        (address resolver, ) = datastore.getResolver(canonicalId);
        return resolver;
    }
    
    /**
     * @dev Required override for UUPSUpgradeable - restricts upgrade permissions
     */
    function _authorizeUpgrade(address) internal override onlyRootRoles(ROLE_UPGRADE) {}
    
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, PermissionedRegistry) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId
            || super.supportsInterface(interfaceId);
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
        
        (MigrationData memory migrationData) = abi.decode(data, (MigrationData));
        MigrationData[] memory migrationDataArray = new MigrationData[](1);
        migrationDataArray[0] = migrationData;
        
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        
        _migrateLockedSubdomains(tokenIds, migrationDataArray);
        
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
        
        (MigrationData[] memory migrationDataArray) = abi.decode(data, (MigrationData[]));
        
        _migrateLockedSubdomains(tokenIds, migrationDataArray);
        
        return this.onERC1155BatchReceived.selector;
    }
    
    function _migrateLockedSubdomains(uint256[] memory tokenIds, MigrationData[] memory migrationDataArray) internal {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            (, uint32 fuses, ) = nameWrapper.getData(tokenIds[i]);
            
            // Ensure name meets migration requirements
            LibLockedNames.validateLockedName(fuses, tokenIds[i]);
            
            // Ensure proper domain hierarchy for migration
            _validateHierarchy(migrationDataArray[i].dnsEncodedName, migrationDataArray[i].transferData.label);
            
            // Create dedicated registry for the migrated name
            address subregistry = LibLockedNames.deployMigratedRegistry(
                factory,
                address(this),
                migrationDataArray[i].transferData.owner,
                migrationDataArray[i].salt,
                migrationDataArray[i].dnsEncodedName
            );
            
            // Determine permissions from name configuration
            uint256 roleBitmap = LibLockedNames.generateRoleBitmapFromFuses(fuses);
            
            // Complete name registration in new registry
            _register(
                migrationDataArray[i].transferData.label,
                migrationDataArray[i].transferData.owner,
                IRegistry(subregistry),
                migrationDataArray[i].transferData.resolver,
                roleBitmap,
                migrationDataArray[i].transferData.expires
            );
            
            // Finalize migration by freezing the name
            LibLockedNames.freezeName(nameWrapper, tokenIds[i], fuses);
        }
    }
    
    function _validateHierarchy(bytes memory dnsEncodedName, string memory label) internal view {
        // Check if label is already registered in this registry
        uint256 canonicalId = NameUtils.labelToCanonicalId(label);
        (, uint64 expires, ) = datastore.getSubregistry(canonicalId);
        if (expires > 0 && expires > block.timestamp) {
            revert IStandardRegistry.NameAlreadyRegistered(label);
        }
        
        // Extract parent domain information for validation
        (string memory parentLabel, uint256 parentOffset) = _getParentLabel(dnsEncodedName);
        
        // Check if parent exists in current registry system
        uint256 parentCanonicalId = NameUtils.labelToCanonicalId(parentLabel);
        (, uint64 parentExpires, ) = datastore.getSubregistry(parentCanonicalId);
        bool existsInCurrent = (parentExpires > 0 && parentExpires > block.timestamp);
        
        // Compute domain hash for legacy system check
        bytes32 parentNode = dnsEncodedName.namehash(parentOffset);
        
        // Check if parent exists in legacy system and we control it
        bool controlledInLegacy = nameWrapper.isWrapped(parentNode) && 
                                  nameWrapper.ownerOf(uint256(parentNode)) == address(this);
        
        // Both conditions must be true for valid hierarchy
        if (existsInCurrent && controlledInLegacy) {
            return;
        }
        
        // Parent is not properly migrated - either not in current registry or not controlled in legacy
        revert ParentNotMigrated(dnsEncodedName, parentOffset);
    }
    
    function _getParentLabel(bytes memory dnsEncodedName) internal pure returns (string memory parentLabel, uint256 parentOffset) {
        // Move past child label to access parent
        (, parentOffset) = NameCoder.nextLabel(dnsEncodedName, 0);
        
        // Ensure parent domain exists
        if (dnsEncodedName[parentOffset] == 0) {
            revert NoParentDomain();
        }
        
        // Read parent domain name from encoded data
        (uint8 parentLabelSize, ) = NameCoder.nextLabel(dnsEncodedName, parentOffset);
        parentLabel = new string(parentLabelSize);
        assembly {
            mcopy(add(parentLabel, 32), add(add(dnsEncodedName, 33), parentOffset), parentLabelSize)
        }
    }
}