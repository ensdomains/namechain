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

/**
 * @title MigratedWrappedNameRegistry
 * @dev A registry for migrated wrapped names that inherits from PermissionedRegistry and is upgradeable using the UUPS pattern.
 * This contract provides resolver fallback to the universal resolver for names that haven't been migrated yet.
 */
contract MigratedWrappedNameRegistry is Initializable, PermissionedRegistry, UUPSUpgradeable {
    uint256 internal constant ROLE_UPGRADE = 1 << 20;
    uint256 internal constant ROLE_UPGRADE_ADMIN = ROLE_UPGRADE << 128;
    
    IUniversalResolver public universalResolver;

    constructor() PermissionedRegistry(IRegistryDatastore(address(0)), IRegistryMetadata(address(0)), _msgSender(), 0) {
        // This disables initialization for the implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the MigratedWrappedNameRegistry contract.
     * @param _datastore The registry datastore contract.
     * @param _metadata The registry metadata contract.
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
}