// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {SimpleRegistryMetadata} from "../common/SimpleRegistryMetadata.sol";
import {PermissionedRegistry} from "../common/PermissionedRegistry.sol";
import {IRegistryDatastore} from "../common/IRegistryDatastore.sol";
import {IRegistryMetadata} from "../common/IRegistryMetadata.sol";
import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {INameWrapper, PARENT_CANNOT_CONTROL} from "@ens/contracts/wrapper/INameWrapper.sol";
import {LibLockedNames} from "./LibLockedNames.sol";
import {ENS} from "@ens/contracts/registry/ENS.sol";
import {TransferData, MigrationData} from "../common/TransferData.sol";
import {LibRegistryRoles} from "../common/LibRegistryRoles.sol";
import {VerifiableFactory} from "../../lib/verifiable-factory/src/VerifiableFactory.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {IStandardRegistry} from "../common/IStandardRegistry.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {RegistryUtils} from "@ens/contracts/universalResolver/RegistryUtils.sol";
import {IMigratedWrappedNameRegistry} from "./IMigratedWrappedNameRegistry.sol";
import "./MigrationErrors.sol";
import "../common/Errors.sol";

/**
 * @title MigratedWrappedNameRegistry
 * @dev A registry for migrated wrapped names that inherits from PermissionedRegistry and is upgradeable using the UUPS pattern.
 * This contract provides resolver fallback to the universal resolver for names that haven't been migrated yet.
 * It also handles subdomain migration by receiving NFT transfers from the NameWrapper.
 */
contract MigratedWrappedNameRegistry is Initializable, PermissionedRegistry, UUPSUpgradeable, IERC1155Receiver, IMigratedWrappedNameRegistry {
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
     * @param _ownerRoles The roles to grant to the owner.
     * @param _registrarAddress Optional address to grant ROLE_REGISTRAR permissions (typically for testing).
     */
    function initialize(
        bytes calldata _parentDnsEncodedName,
        address _ownerAddress,
        uint256 _ownerRoles,
        address _registrarAddress
    ) public initializer {
        require(_ownerAddress != address(0), "Owner cannot be zero address");
        
        // Set the parent domain for name resolution fallback
        parentDnsEncodedName = _parentDnsEncodedName;
        
        // Configure owner with upgrade permissions and specified roles
        _grantRoles(ROOT_RESOURCE, ROLE_UPGRADE | ROLE_UPGRADE_ADMIN | _ownerRoles, _ownerAddress, false);
        
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
        
        _migrateSubdomains(tokenIds, migrationDataArray);
        
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
        
        _migrateSubdomains(tokenIds, migrationDataArray);
        
        return this.onERC1155BatchReceived.selector;
    }
    
    function _migrateSubdomains(uint256[] memory tokenIds, MigrationData[] memory migrationDataArray) internal {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            (, uint32 fuses, ) = nameWrapper.getData(tokenIds[i]);
            
            // Ensure name meets migration requirements
            LibLockedNames.validateEmancipatedName(fuses, tokenIds[i]);
            
            // Ensure proper domain hierarchy for migration
            string memory label = _validateHierarchy(migrationDataArray[i].transferData.dnsEncodedName, 0);
            
            // Determine permissions from name configuration (allow subdomain renewal based on fuses)
            (uint256 tokenRoles, uint256 subRegistryRoles) = LibLockedNames.generateRoleBitmapsFromFuses(fuses);
            
            // Create dedicated registry for the migrated name
            address subregistry = LibLockedNames.deployMigratedRegistry(
                factory,
                ERC1967Utils.getImplementation(),
                migrationDataArray[i].transferData.owner,
                subRegistryRoles,
                migrationDataArray[i].salt,
                migrationDataArray[i].transferData.dnsEncodedName
            );
            
            // Complete name registration in new registry
            _register(
                label,
                migrationDataArray[i].transferData.owner,
                IRegistry(subregistry),
                migrationDataArray[i].transferData.resolver,
                tokenRoles,
                migrationDataArray[i].transferData.expires
            );
            
            // Finalize migration by freezing the name
            LibLockedNames.freezeName(nameWrapper, tokenIds[i], fuses);
        }
    }
    
    function _validateHierarchy(bytes memory dnsEncodedName, uint256 offset) internal view returns (string memory label) {
        // Extract the current label (leftmost, at offset 0)
        uint256 parentOffset;
        (label, parentOffset) = NameUtils.extractLabel(dnsEncodedName, offset);
        
        // Check if there's no parent (trying to migrate TLD)
        if (dnsEncodedName[parentOffset] == 0) {
            revert NoParentDomain();
        }
        
        // Extract the parent label
        (string memory parentLabel, uint256 grandparentOffset) = NameUtils.extractLabel(dnsEncodedName, parentOffset);
        
        // Check if this is a 2LD (parent is "eth" and no grandparent)
        if (keccak256(bytes(parentLabel)) == keccak256(bytes("eth")) && 
            dnsEncodedName[grandparentOffset] == 0) {
            
            // For 2LD: Check that label is NOT registered in ethRegistry
            IRegistry subregistry = ethRegistry.getSubregistry(label);
            if (address(subregistry) != address(0)) {
                revert IStandardRegistry.NameAlreadyRegistered(label);
            }
            
        } else {
            // For 3LD+: Check that parent is wrapped and owned by this contract
            bytes32 parentNode = NameCoder.namehash(dnsEncodedName, parentOffset);
            if (!nameWrapper.isWrapped(parentNode) || 
                nameWrapper.ownerOf(uint256(parentNode)) != address(this)) {
                revert ParentNotMigrated(dnsEncodedName, parentOffset);
            }
            
            // Also check that the current label is NOT already registered in this registry
            IRegistry subregistry = this.getSubregistry(label);
            if (address(subregistry) != address(0)) {
                revert IStandardRegistry.NameAlreadyRegistered(label);
            }
        }
        
        return label;
    }
    
    function _register(
        string memory label, 
        address owner, 
        IRegistry registry, 
        address resolver, 
        uint256 roleBitmap, 
        uint64 expires
    ) internal virtual override returns (uint256 tokenId) {
        // Check if the label has an emancipated NFT in the old system
        // For .eth 2LDs, NameWrapper uses keccak256(label) as the token ID
        uint256 legacyTokenId = uint256(keccak256(bytes(label)));
        (, uint32 fuses, ) = nameWrapper.getData(legacyTokenId);
        
        // If the name is emancipated (PARENT_CANNOT_CONTROL burned), 
        // it must be migrated (owned by this registry)
        if ((fuses & PARENT_CANNOT_CONTROL) != 0) {
            if (nameWrapper.ownerOf(legacyTokenId) != address(this)) {
                revert LabelNotMigrated(label);
            }
        }
        
        // Proceed with registration
        return super._register(label, owner, registry, resolver, roleBitmap, expires);
    }
}