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
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {RegistryUtils} from "@ens/contracts/universalResolver/RegistryUtils.sol";

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
    
    error UnauthorizedCaller(address caller);
    error MigrationFailed();
    error InvalidHierarchy(uint256 tokenId);
    error ParentNotMigrated(bytes32 parentNode);
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
        // This disables initialization for the implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the MigratedWrappedNameRegistry contract.
     * @param _ownerAddress The address that will own this registry.
     * @param _ownerRoles The roles to grant to the owner.
     * @param _parentDnsEncodedName The DNS-encoded name of the parent domain.
     */
    function initialize(
        address _ownerAddress,
        uint256 _ownerRoles,
        bytes calldata _parentDnsEncodedName
    ) public initializer {
        require(_ownerAddress != address(0), "Owner cannot be zero address");
        
        // Store the parent DNS-encoded name
        parentDnsEncodedName = _parentDnsEncodedName;
        
        // Grant roles to the owner
        _grantRoles(ROOT_RESOURCE, _ownerRoles | ROLE_UPGRADE | ROLE_UPGRADE_ADMIN, _ownerAddress, false);
        
        // Grant NameWrapper REGISTRAR role so it can migrate subdomains
        _grantRoles(ROOT_RESOURCE, LibRegistryRoles.ROLE_REGISTRAR, address(nameWrapper), false);
    }

    function getResolver(string calldata label) external view override returns (address) {
        uint256 canonicalId = NameUtils.labelToCanonicalId(label);
        (, uint64 expires, ) = datastore.getSubregistry(canonicalId);
        
        // If name hasn't been registered yet (expiry is 0), fall back to ENS registry
        if (expires == 0) {
            // Build full DNS-encoded name by prepending label to parent DNS name
            bytes memory dnsEncodedName = abi.encodePacked(
                bytes1(uint8(bytes(label).length)),
                label,
                parentDnsEncodedName
            );
            
            // Query the ENS registry for the resolver address using RegistryUtils
            (address resolverAddress, , ) = RegistryUtils.findResolver(ensRegistry, dnsEncodedName, 0);
            return resolverAddress;
        }
        
        // If name has expired, return zero address
        if (expires <= block.timestamp) {
            return address(0);
        }
        
        // Name has been registered, return its resolver (could be address(0))
        (address resolver, ) = datastore.getResolver(canonicalId);
        return resolver;
    }
    
    /**
     * @dev Required override for UUPSUpgradeable - only accounts with ROLE_UPGRADE can upgrade
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
            
            // Validate fuses
            LibLockedNames.validateLockedName(fuses, tokenIds[i]);
            
            // Validate hierarchy - check parent is migrated or controlled
            _validateHierarchy(migrationDataArray[i].dnsEncodedName);
            
            // Deploy MigratedWrappedNameRegistry with transferData.owner as owner
            uint256 salt = uint256(keccak256(migrationDataArray[i].salt));
            
            // For subdomain registries, the parent DNS name is the subdomain's own DNS-encoded name
            address subregistry = LibLockedNames.deployMigratedRegistry(
                factory,
                address(this),
                migrationDataArray[i].transferData.owner,
                salt,
                migrationDataArray[i].dnsEncodedName
            );
            
            // Generate role bitmap based on fuses
            uint256 roleBitmap = LibLockedNames.generateRoleBitmapFromFuses(fuses, true);
            
            _register(
                migrationDataArray[i].transferData.label,
                migrationDataArray[i].transferData.owner,
                IRegistry(subregistry),
                migrationDataArray[i].transferData.resolver,
                roleBitmap,
                migrationDataArray[i].transferData.expires
            );
            
            // Burn all migration fuses
            LibLockedNames.burnAllMigrationFuses(nameWrapper, tokenIds[i]);
        }
    }
    
    function _validateHierarchy(bytes memory dnsEncodedName) internal view {
        // Get parent label and offset for potential namehash computation
        (string memory parentLabel, uint256 parentOffset) = _getParentLabel(dnsEncodedName);
        
        // Check if parent is in v2 registry (this registry) using canonical ID
        uint256 parentCanonicalId = NameUtils.labelToCanonicalId(parentLabel);
        (, uint64 parentExpires, ) = datastore.getSubregistry(parentCanonicalId);
        if (parentExpires > 0 && parentExpires > block.timestamp) {
            // Parent is migrated and not expired - hierarchy is valid
            return;
        }
        
        // Only compute namehash when we need to check v1 NameWrapper
        bytes32 parentNode = dnsEncodedName.namehash(parentOffset);
        
        // Check if parent is still in v1 NameWrapper
        if (nameWrapper.isWrapped(parentNode)) {
            // Parent is still in v1 - check if we control it
            address parentOwner = nameWrapper.ownerOf(uint256(parentNode));
            if (parentOwner == address(this)) {
                // We control the parent in v1 - hierarchy is valid
                return;
            }
        }
        
        // Parent is neither migrated nor controlled
        revert ParentNotMigrated(parentNode);
    }
    
    function _getParentLabel(bytes memory dnsEncodedName) internal pure returns (string memory parentLabel, uint256 parentOffset) {
        // Skip the first label
        (, parentOffset) = NameCoder.nextLabel(dnsEncodedName, 0);
        
        // If there's no parent this is an error
        if (dnsEncodedName[parentOffset] == 0) {
            revert NoParentDomain();
        }
        
        // Extract parent label size and content
        (uint8 parentLabelSize, ) = NameCoder.nextLabel(dnsEncodedName, parentOffset);
        parentLabel = new string(parentLabelSize);
        assembly {
            mcopy(add(parentLabel, 32), add(add(dnsEncodedName, 33), parentOffset), parentLabelSize)
        }
    }
}