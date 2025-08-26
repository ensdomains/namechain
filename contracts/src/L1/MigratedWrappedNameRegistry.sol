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
import {INameWrapper, CANNOT_UNWRAP, CANNOT_BURN_FUSES, CANNOT_TRANSFER, CANNOT_SET_RESOLVER, CANNOT_SET_TTL, CANNOT_CREATE_SUBDOMAIN, CANNOT_APPROVE} from "@ens/contracts/wrapper/INameWrapper.sol";
import {ENS} from "@ens/contracts/registry/ENS.sol";
import {TransferData, MigrationData} from "../common/TransferData.sol";
import {LibRegistryRoles} from "../common/LibRegistryRoles.sol";
import {VerifiableFactory} from "../../lib/verifiable-factory/src/VerifiableFactory.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

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
    error TokenIdMismatch(uint256 tokenId, uint256 expectedTokenId);
    error InconsistentFusesState(uint256 tokenId);
    error NameNotLocked(uint256 tokenId);
    error InvalidHierarchy(uint256 tokenId);
    error ParentNotMigrated(bytes32 parentNode);
    
    IUniversalResolver public universalResolver;
    IUniversalResolver public immutable universalResolverImmutable;
    INameWrapper public immutable nameWrapper;
    ENS public immutable ensRegistry;
    VerifiableFactory public immutable factory;
    address public immutable ethRegistry;

    constructor(
        IUniversalResolver _universalResolver,
        INameWrapper _nameWrapper,
        ENS _ensRegistry,
        VerifiableFactory _factory,
        address _ethRegistry
    ) PermissionedRegistry(IRegistryDatastore(address(0)), IRegistryMetadata(address(0)), _msgSender(), 0) {
        universalResolverImmutable = _universalResolver;
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
     * @param _universalResolver The universal resolver for fallback resolution.
     */
    function initialize(
        IRegistryDatastore _datastore,
        IRegistryMetadata _metadata,
        address _ownerAddress,
        uint256 _ownerRoles,
        IUniversalResolver _universalResolver
    ) public initializer {
        require(_ownerAddress != address(0), "Owner cannot be zero address");
        require(address(_universalResolver) != address(0), "Universal resolver cannot be zero address");
        
        // Initialize datastore
        datastore = _datastore;
        
        // Initialize metadata provider
        if (address(_metadata) == address(0)) {
            // Create a new SimpleRegistryMetadata if none is provided
            _updateMetadataProvider(new SimpleRegistryMetadata());
        } else {
            metadataProvider = _metadata;
        }
        
        // Grant roles to the owner
        _grantRoles(ROOT_RESOURCE, _ownerRoles | ROLE_UPGRADE | ROLE_UPGRADE_ADMIN, _ownerAddress, false);
        
        // Initialize universal resolver
        universalResolver = _universalResolver;
        
        // Grant NameWrapper REGISTRAR role so it can migrate subdomains
        _grantRoles(ROOT_RESOURCE, LibRegistryRoles.ROLE_REGISTRAR, address(nameWrapper), false);
    }

    function getResolver(string calldata label) external view override returns (address) {
        uint256 canonicalId = NameUtils.labelToCanonicalId(label);
        (, uint64 expires, ) = datastore.getSubregistry(canonicalId);
        
        // If name hasn't been registered yet (expiry is 0), call through to universal resolver
        if (expires == 0) {
            // Prepare the name for universal resolver query
            // For 2LD names, we need to construct the full name with .eth suffix
            bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(label);
            
            // Query the universal resolver for the resolver address
            // Note: The universal resolver will return the resolver from the v1 NameWrapper
            try universalResolver.findResolver(dnsEncodedName) returns (address v1Resolver, bytes32, uint256) {
                return v1Resolver;
            } catch {
                return address(0);
            }
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
            
            // Check if name is locked
            if (fuses & CANNOT_UNWRAP == 0) {
                revert NameNotLocked(tokenIds[i]);
            }
            
            // Cannot migrate if CANNOT_BURN_FUSES is already burnt
            if ((fuses & CANNOT_BURN_FUSES) != 0) {
                revert InconsistentFusesState(tokenIds[i]);
            }
            
            // EARLY validation: Validate that tokenId matches the namehash
            bytes32 expectedNode = _computeNamehash(migrationDataArray[i].dnsEncodedName);
            if (bytes32(tokenIds[i]) != expectedNode) {
                revert TokenIdMismatch(tokenIds[i], uint256(expectedNode));
            }
            
            // Validate hierarchy - check parent is migrated or controlled
            _validateHierarchy(migrationDataArray[i].dnsEncodedName);
            
            // Create new MigratedWrappedNameRegistry for this subdomain using factory
            uint256 salt = uint256(keccak256(migrationDataArray[i].salt));
            bytes memory initData = abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                datastore,
                metadataProvider,
                address(this),
                LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_REGISTRAR_ADMIN,
                universalResolverImmutable
            );
            address subregistry = factory.deployProxy(address(this), salt, initData);
            
            // Setup roles based on fuses
            uint256 roleBitmap = LibRegistryRoles.ROLE_RENEW | LibRegistryRoles.ROLE_RENEW_ADMIN;
            if (fuses & CANNOT_SET_RESOLVER == 0) {
                roleBitmap = roleBitmap | LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN;
            }
            if (fuses & CANNOT_CREATE_SUBDOMAIN == 0) {
                roleBitmap = roleBitmap | LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_REGISTRAR_ADMIN;
            }
            
            _register(
                migrationDataArray[i].transferData.label,
                migrationDataArray[i].transferData.owner,
                IRegistry(subregistry),
                migrationDataArray[i].transferData.resolver,
                roleBitmap,
                migrationDataArray[i].transferData.expires
            );
            
            // Burn all required fuses on the NameWrapper token
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
    
    function _validateHierarchy(bytes memory dnsEncodedName) internal view {
        // Decode the DNS name to get parent
        (, bytes32 parentNode) = _getParentNode(dnsEncodedName);
        
        // Check if parent is in v2 registry (this registry)
        (, uint64 parentExpires, ) = datastore.getSubregistry(uint256(parentNode));
        if (parentExpires > 0 && parentExpires > block.timestamp) {
            // Parent is migrated and not expired - hierarchy is valid
            return;
        }
        
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
    
    function _getParentNode(bytes memory dnsEncodedName) internal pure returns (bytes memory parentName, bytes32 parentNode) {
        // Skip the first label to get parent
        uint256 labelLength = uint256(uint8(dnsEncodedName[0]));
        uint256 offset = labelLength + 1;
        
        // Extract parent DNS name
        parentName = new bytes(dnsEncodedName.length - offset);
        for (uint256 i = 0; i < parentName.length; i++) {
            parentName[i] = dnsEncodedName[offset + i];
        }
        
        // Compute parent namehash
        parentNode = _computeNamehash(parentName);
    }
    
    function _computeNamehash(bytes memory dnsEncodedName) internal pure returns (bytes32) {
        return dnsEncodedName.namehash(0);
    }
}