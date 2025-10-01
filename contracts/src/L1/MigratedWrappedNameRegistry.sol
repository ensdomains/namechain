// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ENS} from "@ens/contracts/registry/ENS.sol";
import {RegistryUtils} from "@ens/contracts/universalResolver/RegistryUtils.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {INameWrapper, PARENT_CANNOT_CONTROL} from "@ens/contracts/wrapper/INameWrapper.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {UnauthorizedCaller} from "./../common/Errors.sol";
import {IPermissionedRegistry} from "./../common/IPermissionedRegistry.sol";
import {IRegistry} from "./../common/IRegistry.sol";
import {IRegistryDatastore} from "./../common/IRegistryDatastore.sol";
import {IRegistryMetadata} from "./../common/IRegistryMetadata.sol";
import {IStandardRegistry} from "./../common/IStandardRegistry.sol";
import {LibRegistryRoles} from "./../common/LibRegistryRoles.sol";
import {NameUtils} from "./../common/NameUtils.sol";
import {PermissionedRegistry} from "./../common/PermissionedRegistry.sol";
import {MigrationData} from "./../common/TransferData.sol";
import {IMigratedWrappedNameRegistry} from "./IMigratedWrappedNameRegistry.sol";
import {LibLockedNames} from "./LibLockedNames.sol";
import {ParentNotMigrated, LabelNotMigrated} from "./MigrationErrors.sol";

/**
 * @title MigratedWrappedNameRegistry
 * @dev A registry for migrated wrapped names that inherits from PermissionedRegistry and is upgradeable using the UUPS pattern.
 * This contract provides resolver fallback to the universal resolver for names that haven't been migrated yet.
 * It also handles subdomain migration by receiving NFT transfers from the NameWrapper.
 */
contract MigratedWrappedNameRegistry is
    Initializable,
    PermissionedRegistry,
    UUPSUpgradeable,
    IERC1155Receiver,
    IMigratedWrappedNameRegistry
{
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    uint256 internal constant _ROLE_UPGRADE = 1 << 20;
    uint256 internal constant _ROLE_UPGRADE_ADMIN = _ROLE_UPGRADE << 128;

    INameWrapper public immutable NAME_WRAPPER;

    ENS public immutable ENS_REGISTRY;

    VerifiableFactory public immutable FACTORY;

    IPermissionedRegistry public immutable ETH_REGISTRY;

    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    bytes public parentDnsEncodedName;

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    error NoParentDomain();

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        INameWrapper nameWrapper_,
        ENS ensRegistry_,
        VerifiableFactory factory_,
        IPermissionedRegistry ethRegistry_,
        IRegistryDatastore datastore_,
        IRegistryMetadata metadataProvider_
    ) PermissionedRegistry(datastore_, metadataProvider_, _msgSender(), 0) {
        NAME_WRAPPER = nameWrapper_;
        ENS_REGISTRY = ensRegistry_;
        FACTORY = factory_;
        ETH_REGISTRY = ethRegistry_;
        // Prevents initialization on the implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the MigratedWrappedNameRegistry contract.
     * @param parentDnsEncodedName_ The DNS-encoded name of the parent domain.
     * @param ownerAddress_ The address that will own this registry.
     * @param ownerRoles_ The roles to grant to the owner.
     * @param registrarAddress_ Optional address to grant ROLE_REGISTRAR permissions (typically for testing).
     */
    function initialize(
        bytes calldata parentDnsEncodedName_,
        address ownerAddress_,
        uint256 ownerRoles_,
        address registrarAddress_
    ) public initializer {
        // TODO: custom error
        require(ownerAddress_ != address(0), "Owner cannot be zero address");

        // Set the parent domain for name resolution fallback
        parentDnsEncodedName = parentDnsEncodedName_;

        // Configure owner with upgrade permissions and specified roles
        _grantRoles(
            ROOT_RESOURCE,
            _ROLE_UPGRADE | _ROLE_UPGRADE_ADMIN | ownerRoles_,
            ownerAddress_,
            false
        );

        // Grant registrar role if specified (typically for testing)
        if (registrarAddress_ != address(0)) {
            _grantRoles(ROOT_RESOURCE, LibRegistryRoles.ROLE_REGISTRAR, registrarAddress_, false);
        }
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC165, PermissionedRegistry) returns (bool) {
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
        if (msg.sender != address(NAME_WRAPPER)) {
            revert UnauthorizedCaller(msg.sender);
        }

        (MigrationData[] memory migrationDataArray) = abi.decode(data, (MigrationData[]));

        _migrateSubdomains(tokenIds, migrationDataArray);

        return this.onERC1155BatchReceived.selector;
    }

    function getResolver(string calldata label) external view override returns (address) {
        uint256 canonicalId = NameUtils.labelToCanonicalId(label);
        IRegistryDatastore.Entry memory entry = DATASTORE.getEntry(address(this), canonicalId);
        uint64 expires = entry.expiry;

        // Use fallback resolver for unregistered names
        if (expires == 0) {
            // Construct complete domain name for registry lookup
            bytes memory dnsEncodedName = abi.encodePacked(
                bytes1(uint8(bytes(label).length)),
                label,
                parentDnsEncodedName
            );

            // Retrieve resolver from legacy registry system
            (address resolverAddress, , ) = RegistryUtils.findResolver(
                ENS_REGISTRY,
                dnsEncodedName,
                0
            );
            return resolverAddress;
        }

        // Return no resolver for expired names
        if (expires <= block.timestamp) {
            return address(0);
        }

        // Return the configured resolver for registered names
        return entry.resolver;
    }

    function renew(
        uint256 tokenId,
        uint64 expires
    )
        public
        override(IMigratedWrappedNameRegistry, PermissionedRegistry)
        onlyNonExpiredTokenRoles(tokenId, LibRegistryRoles.ROLE_RENEW)
    {
        super.renew(tokenId, expires);
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    /**
     * @dev Required override for UUPSUpgradeable - restricts upgrade permissions
     */
    function _authorizeUpgrade(address) internal override onlyRootRoles(_ROLE_UPGRADE) {}

    function _migrateSubdomains(
        uint256[] memory tokenIds,
        MigrationData[] memory migrationDataArray
    ) internal {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            (, uint32 fuses, ) = NAME_WRAPPER.getData(tokenIds[i]);

            // Ensure name meets migration requirements
            LibLockedNames.validateEmancipatedName(fuses, tokenIds[i]);

            // Ensure proper domain hierarchy for migration
            string memory label = _validateHierarchy(
                migrationDataArray[i].transferData.dnsEncodedName,
                0
            );

            // Determine permissions from name configuration (allow subdomain renewal based on fuses)
            (uint256 tokenRoles, uint256 subRegistryRoles) = LibLockedNames
                .generateRoleBitmapsFromFuses(fuses);

            // Create dedicated registry for the migrated name
            address subregistry = LibLockedNames.deployMigratedRegistry(
                FACTORY,
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
            LibLockedNames.freezeName(NAME_WRAPPER, tokenIds[i], fuses);
        }
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
        (, uint32 fuses, ) = NAME_WRAPPER.getData(legacyTokenId);

        // If the name is emancipated (PARENT_CANNOT_CONTROL burned),
        // it must be migrated (owned by this registry)
        if ((fuses & PARENT_CANNOT_CONTROL) != 0) {
            if (NAME_WRAPPER.ownerOf(legacyTokenId) != address(this)) {
                revert LabelNotMigrated(label);
            }
        }

        // Proceed with registration
        return super._register(label, owner, registry, resolver, roleBitmap, expires);
    }

    function _validateHierarchy(
        bytes memory dnsEncodedName,
        uint256 offset
    ) internal view returns (string memory label) {
        // Extract the current label (leftmost, at offset 0)
        uint256 parentOffset;
        (label, parentOffset) = NameUtils.extractLabel(dnsEncodedName, offset);

        // Check if there's no parent (trying to migrate TLD)
        if (dnsEncodedName[parentOffset] == 0) {
            revert NoParentDomain();
        }

        // Extract the parent label
        (string memory parentLabel, uint256 grandparentOffset) = NameUtils.extractLabel(
            dnsEncodedName,
            parentOffset
        );

        // Check if this is a 2LD (parent is "eth" and no grandparent)
        if (
            keccak256(bytes(parentLabel)) == keccak256(bytes("eth")) &&
            dnsEncodedName[grandparentOffset] == 0
        ) {
            // For 2LD: Check that label is NOT registered in ethRegistry
            IRegistry subregistry = ETH_REGISTRY.getSubregistry(label);
            if (address(subregistry) != address(0)) {
                revert IStandardRegistry.NameAlreadyRegistered(label);
            }
        } else {
            // For 3LD+: Check that parent is wrapped and owned by this contract
            bytes32 parentNode = NameCoder.namehash(dnsEncodedName, parentOffset);
            if (
                !NAME_WRAPPER.isWrapped(parentNode) ||
                NAME_WRAPPER.ownerOf(uint256(parentNode)) != address(this)
            ) {
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
}
