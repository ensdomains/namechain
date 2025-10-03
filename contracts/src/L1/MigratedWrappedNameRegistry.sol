// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {console} from "forge-std/Test.sol";

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
import {MigrationErrors} from "./MigrationErrors.sol";
import {InvalidOwner} from "../common/Errors.sol";

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

    VerifiableFactory public immutable MIGRATED_REGISTRY_FACTORY;

    IPermissionedRegistry public immutable ETH_REGISTRY;

    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    bytes32 public parentNode;

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        INameWrapper nameWrapper,
        VerifiableFactory factory_,
        IPermissionedRegistry ethRegistry,
        IRegistryDatastore datastore,
        IRegistryMetadata metadataProvider
    ) PermissionedRegistry(datastore, metadataProvider, _msgSender(), 0) {
        NAME_WRAPPER = nameWrapper;
        MIGRATED_REGISTRY_FACTORY = factory_;
        ETH_REGISTRY = ethRegistry;
        // Prevents initialization on the implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the MigratedWrappedNameRegistry contract.
     * @param args.parentNode The namehash.
     * @param args.owner The address that will own this registry.
     * @param args.ownerRoles The roles to grant to the owner.
     * @param args.registrar Optional address to grant ROLE_REGISTRAR permissions (typically for testing).
     */
    function initialize(Args calldata args) public initializer {
        if (args.owner == address(0)) {
            revert InvalidOwner();
        }

        // Set the parent domain for name resolution fallback
        parentNode = args.parentNode;

        // Configure owner with upgrade permissions and specified roles
        _grantRoles(
            ROOT_RESOURCE,
            _ROLE_UPGRADE | _ROLE_UPGRADE_ADMIN | args.ownerRoles,
            args.owner,
            false
        );

        // Grant registrar role if specified (typically for testing)
        if (args.registrar != address(0)) {
            _grantRoles(ROOT_RESOURCE, LibRegistryRoles.ROLE_REGISTRAR, args.registrar, false);
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

    function parentName() public view returns (bytes memory) {
        return NAME_WRAPPER.names(parentNode);
    }

    function onERC1155Received(
        address /*operator*/,
        address /*from*/,
        uint256 id,
        uint256 /*amount*/,
        bytes calldata data
    ) external virtual returns (bytes4) {
        require(msg.sender == address(NAME_WRAPPER), MigrationErrors.ERROR_ONLY_NAME_WRAPPER);
        _migrateSubdomain(id, abi.decode(data, (MigrationData)), true);
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address /*operator*/,
        address /*from*/,
        uint256[] memory ids,
        uint256[] memory /*amounts*/,
        bytes calldata data
    ) external virtual returns (bytes4) {
        require(msg.sender == address(NAME_WRAPPER), MigrationErrors.ERROR_ONLY_NAME_WRAPPER);
        MigrationData[] memory mds = abi.decode(data, (MigrationData[]));
        require(ids.length == mds.length, MigrationErrors.ERROR_ARRAY_LENGTH_MISMATCH);
        //revert IERC1155Errors.ERC1155InvalidArrayLength(ids.length, mds.length);
        for (uint256 i; i < ids.length; ++i) {
            _migrateSubdomain(ids[i], mds[i], true);
        }
        return this.onERC1155BatchReceived.selector;
    }

    function getResolver(string calldata label) external view override returns (address) {
        (, IRegistryDatastore.Entry memory entry) = getNameData(label);
        // Use fallback resolver for unregistered names
        if (_isExpired(entry.expiry)) {
            // Retrieve resolver from legacy registry system
            (address resolver, , ) = RegistryUtils.findResolver(
                NAME_WRAPPER.ens(),
                NameUtils.append(parentName(), label),
                0
            );
            return resolver;
        } else {
            return entry.resolver;
        }
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    /**
     * @dev Required override for UUPSUpgradeable - restricts upgrade permissions
     */
    function _authorizeUpgrade(address) internal override onlyRootRoles(_ROLE_UPGRADE) {}

    function _migrateSubdomain(uint256 id, MigrationData memory md, bool viaReceiver) internal {
        (, uint32 fuses, uint64 expiry) = NAME_WRAPPER.getData(id);
        bytes memory name = NAME_WRAPPER.names(bytes32(id));
        string memory label = _validateHierarchy(name);

        if ((fuses & PARENT_CANNOT_CONTROL) == 0) {
            if (viaReceiver) {
                revert(MigrationErrors.ERROR_NAME_NOT_EMANCIPATED);
            } else {
                revert MigrationErrors.NameNotEmancipated(name);
            }
        }

        // Determine permissions from name configuration (allow subdomain renewal based on fuses)
        (uint256 tokenRoles, uint256 subRegistryRoles) = LibLockedNames
            .generateRoleBitmapsFromFuses(fuses);

        // Create dedicated registry for the migrated name

        address subregistry = MIGRATED_REGISTRY_FACTORY.deployProxy(
            ERC1967Utils.getImplementation(),
            md.salt,
            abi.encodeCall(
                IMigratedWrappedNameRegistry.initialize,
                (
                    IMigratedWrappedNameRegistry.Args({
                        parentNode: bytes32(id),
                        owner: md.transferData.owner,
                        ownerRoles: subRegistryRoles,
                        registrar: address(0)
                    })
                )
            )
        );

        // address subregistry = LibLockedNames.deployMigratedRegistry(
        //     MIGRATED_REGISTRY_FACTORY,
        //     ERC1967Utils.getImplementation(),
        //     migrationDataArray[i].transferData.owner,
        //     subRegistryRoles,
        //     migrationDataArray[i].salt,
        //     migrationDataArray[i].transferData.name
        // );

        // Complete name registration in new registry
        _register(
            label,
            md.transferData.owner,
            IRegistry(subregistry),
            md.transferData.resolver,
            tokenRoles,
            expiry //md.transferData.expiry
        );

        // Finalize migration by freezing the name
        LibLockedNames.freezeName(NAME_WRAPPER, id, fuses);
    }

    function _register(
        string memory label,
        address owner,
        IRegistry registry,
        address resolver,
        uint256 roleBitmap,
        uint64 expiry
    ) internal virtual override returns (uint256 tokenId) {
        // Check if the label has an emancipated NFT in the old system
        // For .eth 2LDs, NameWrapper uses keccak256(label) as the token ID

        bytes32 node = NameCoder.namehash(parentNode, keccak256(bytes(label)));
        (, uint32 fuses, ) = NAME_WRAPPER.getData(uint256(node));

        // If the name is emancipated (PARENT_CANNOT_CONTROL burned),
        // it must be migrated (owned by this registry)
        if (
            (fuses & PARENT_CANNOT_CONTROL) != 0 &&
            NAME_WRAPPER.ownerOf(uint256(node)) != address(this)
        ) {
            revert MigrationErrors.NameNotMigrated(NameUtils.append(parentName(), label));
        }

        // Proceed with registration
        return super._register(label, owner, registry, resolver, roleBitmap, expiry);
    }

    function _validateHierarchy(bytes memory name) internal view returns (string memory label) {
        uint256 offset;
        (label, offset) = NameUtils.extractLabel(name, offset);

        // ensure child of parent
        if (bytes(label).length == 0 || NameCoder.namehash(name, offset) != parentNode) {
            revert MigrationErrors.NameNotSubdomain(name, parentName());
        }

        // find subregistry
        IRegistry subregistry;
        if (parentNode == NameUtils.ETH_NODE) {
            subregistry = ETH_REGISTRY.getSubregistry(label);
        } else {
            if (
                !NAME_WRAPPER.isWrapped(parentNode) ||
                NAME_WRAPPER.ownerOf(uint256(parentNode)) != address(this)
            ) {
                revert MigrationErrors.NameNotMigrated(parentName());
            }
            subregistry = this.getSubregistry(label);
        }

        // check NOT already registered
        if (address(subregistry) != address(0)) {
            revert IStandardRegistry.NameAlreadyRegistered(label);
        }

        return label;
    }
}
