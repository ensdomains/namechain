// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {INameWrapper, PARENT_CANNOT_CONTROL} from "@ens/contracts/wrapper/INameWrapper.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {InvalidOwner} from "../../common/CommonErrors.sol";
import {IRegistry} from "../../common/registry/interfaces/IRegistry.sol";
import {IRegistryDatastore} from "../../common/registry/interfaces/IRegistryDatastore.sol";
import {IRegistryMetadata} from "../../common/registry/interfaces/IRegistryMetadata.sol";
import {RegistryRolesLib} from "../../common/registry/libraries/RegistryRolesLib.sol";
import {PermissionedRegistry} from "../../common/registry/PermissionedRegistry.sol";
import {LockedNamesLib} from "../migration/libraries/LockedNamesLib.sol";
import {MigrationErrors} from "../migration/libraries/MigrationErrors.sol";
import {IMigratedWrapperRegistry} from "../registry/interfaces/IMigratedWrapperRegistry.sol";

/**
 * @title MigratedWrapperRegistry
 * @dev A registry for migrated wrapped names that inherits from PermissionedRegistry and is upgradeable using the UUPS pattern.
 * This contract provides resolver fallback to the universal resolver for names that haven't been migrated yet.
 * It also handles subdomain migration by receiving NFT transfers from the NameWrapper.
 */
contract MigratedWrapperRegistry is
    Initializable,
    PermissionedRegistry,
    IERC1155Receiver,
    IMigratedWrapperRegistry
{
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    bytes32 private constant _PAYLOAD_HASH = keccak256("MigratedWrapperRegistry");

    INameWrapper public immutable NAME_WRAPPER;

    address public immutable FALLBACK_RESOLVER;

    VerifiableFactory public immutable FACTORY;

    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    bytes32 public parentNode;

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        INameWrapper nameWrapper,
        address fallbackResolver,
        VerifiableFactory factory,
        IRegistryDatastore datastore,
        IRegistryMetadata metadataProvider
    ) PermissionedRegistry(datastore, metadataProvider, _msgSender(), 0) {
        NAME_WRAPPER = nameWrapper;
        FALLBACK_RESOLVER = fallbackResolver;
        FACTORY = factory;
        // Prevents initialization on the implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the MigratedWrapperRegistry contract.
     * @param args.parentNode The namehash.
     * @param args.owner The address that will own this registry.
     * @param args.ownerRoles The roles to grant to the owner.
     * @param args.registrar Optional address to grant ROLE_REGISTRAR permissions (typically for testing).
     */
    function initialize(IMigratedWrapperRegistry.ConstructorArgs calldata args) public initializer {
        if (args.owner == address(0)) {
            revert InvalidOwner();
        }

        // Set the parent domain for name resolution fallback
        parentNode = args.parentNode;

        // Configure owner with upgrade permissions and specified roles
        _grantRoles(
            ROOT_RESOURCE,
            RegistryRolesLib.ROLE_UPGRADE | RegistryRolesLib.ROLE_UPGRADE_ADMIN | args.ownerRoles,
            args.owner,
            false
        );

        // Grant registrar role if specified (typically for testing)
        if (args.registrar != address(0)) {
            _grantRoles(ROOT_RESOURCE, RegistryRolesLib.ROLE_REGISTRAR, args.registrar, false);
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

    function migrate(Data calldata md) external returns (uint256 tokenId) {
        NAME_WRAPPER.safeTransferFrom(
            msg.sender,
            address(this),
            uint256(md.node),
            1,
            abi.encode(_PAYLOAD_HASH)
        );
        return _finishMigration(md);
    }

    // TODO: should this return tokenIds[]?
    function migrate(Data[] calldata mds) external {
        uint256[] memory ids = new uint256[](mds.length);
        uint256[] memory amounts = new uint256[](mds.length);
        for (uint256 i; i < mds.length; ++i) {
            ids[i] = uint256(mds[i].node);
            amounts[i] = 1;
        }
        NAME_WRAPPER.safeBatchTransferFrom(
            msg.sender,
            address(this),
            ids,
            amounts,
            abi.encode(_PAYLOAD_HASH)
        );
        for (uint256 i; i < mds.length; ++i) {
            _finishMigration(mds[i]);
        }
    }

    function onERC1155Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*id*/,
        uint256 /*amount*/,
        bytes calldata data
    ) external view returns (bytes4) {
        require(msg.sender == address(NAME_WRAPPER), MigrationErrors.ERROR_ONLY_NAME_WRAPPER);
        require(bytes32(data) == _PAYLOAD_HASH, MigrationErrors.ERROR_UNEXPECTED_TRANSFER);
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address /*operator*/,
        address /*from*/,
        uint256[] calldata /*ids*/,
        uint256[] calldata /*amounts*/,
        bytes calldata data
    ) external view returns (bytes4) {
        require(msg.sender == address(NAME_WRAPPER), MigrationErrors.ERROR_ONLY_NAME_WRAPPER);
        require(bytes32(data) == _PAYLOAD_HASH, MigrationErrors.ERROR_UNEXPECTED_TRANSFER);
        return this.onERC1155BatchReceived.selector;
    }

    function getResolver(
        string calldata label
    ) external view override(IRegistry, PermissionedRegistry) returns (address) {
        (, IRegistryDatastore.Entry memory entry) = getNameData(label);
        // Use fallback resolver for unregistered names
        if (_isExpired(entry.expiry)) {
            return FALLBACK_RESOLVER;
        } else {
            return entry.resolver;
        }
    }

    function parentName() public view returns (bytes memory) {
        return NAME_WRAPPER.names(parentNode);
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    // TODO: lib/verifiable-factory is not upgradeable
    // /**
    //  * @dev Required override for UUPSUpgradeable - restricts upgrade permissions
    //  */
    // function _authorizeUpgrade(
    //     address
    // ) internal override onlyRootRoles(RegistryRolesLib.ROLE_UPGRADE) {}

    function _finishMigration(Data memory md) internal returns (uint256 tokenId) {
        (, uint32 fuses, uint64 expiry) = NAME_WRAPPER.getData(uint256(md.node));
        bytes memory name = NAME_WRAPPER.names(md.node);
        string memory label = NameCoder.firstLabel(name);

        if (NameCoder.namehash(parentNode, keccak256(bytes(label))) != md.node) {
            revert MigrationErrors.NameNotSubdomain(name, parentName());
        }

        if ((fuses & PARENT_CANNOT_CONTROL) == 0) {
            revert MigrationErrors.NameNotEmancipated(name);
        }

        // Determine permissions from name configuration (allow subdomain renewal based on fuses)
        (uint256 tokenRoles, uint256 subRegistryRoles) = LockedNamesLib
            .generateRoleBitmapsFromFuses(fuses);

        // Create dedicated registry for the migrated name
        IRegistry subregistry = IRegistry(
            FACTORY.deployProxy(
                ERC1967Utils.getImplementation(),
                md.salt,
                abi.encodeCall(
                    IMigratedWrapperRegistry.initialize,
                    (
                        IMigratedWrapperRegistry.ConstructorArgs({
                            parentNode: md.node,
                            owner: md.owner,
                            ownerRoles: subRegistryRoles,
                            registrar: address(0)
                        })
                    )
                )
            )
        );

        tokenId = super._register(label, md.owner, subregistry, md.resolver, tokenRoles, expiry);

        LockedNamesLib.freezeName(NAME_WRAPPER, uint256(md.node), fuses);
    }

    function _register(
        string memory label,
        address owner,
        IRegistry registry,
        address resolver,
        uint256 roleBitmap,
        uint64 expiry
    ) internal virtual override returns (uint256 tokenId) {
        // If the name is emancipated (PARENT_CANNOT_CONTROL burned),
        // it must be migrated (owned by this registry)
        bytes32 node = NameCoder.namehash(parentNode, keccak256(bytes(label)));
        (, uint32 fuses, ) = NAME_WRAPPER.getData(uint256(node));
        if ((fuses & PARENT_CANNOT_CONTROL) != 0) {
            revert MigrationErrors.NameNotMigrated(NameCoder.addLabel(parentName(), label));
        }
        return super._register(label, owner, registry, resolver, roleBitmap, expiry);
    }
}
