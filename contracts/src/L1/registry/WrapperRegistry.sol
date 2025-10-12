// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {INameWrapper, PARENT_CANNOT_CONTROL} from "@ens/contracts/wrapper/INameWrapper.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {TransferData} from "../../common/bridge/types/TransferData.sol";
import {CommonErrors} from "../../common/CommonErrors.sol";
import {IRegistry} from "../../common/registry/interfaces/IRegistry.sol";
import {IRegistryDatastore} from "../../common/registry/interfaces/IRegistryDatastore.sol";
import {IRegistryMetadata} from "../../common/registry/interfaces/IRegistryMetadata.sol";
import {RegistryRolesLib} from "../../common/registry/libraries/RegistryRolesLib.sol";
import {PermissionedRegistry} from "../../common/registry/PermissionedRegistry.sol";
import {WrapperReceiver} from "../migration/WrapperReceiver.sol";
import {
    IMigratedWrappedNameRegistry
} from "../registry/interfaces/IMigratedWrappedNameRegistry.sol";

contract WrapperRegistry is
    WrapperReceiver,
    Initializable,
    PermissionedRegistry,
    IMigratedWrappedNameRegistry
{
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    address public immutable FALLBACK_RESOLVER;

    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    bytes32 public parentNode;

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    error NameNotMigrated(bytes name);

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        INameWrapper nameWrapper,
        VerifiableFactory migratedRegistryFactory,
        address fallbackResolver,
        IRegistryDatastore datastore,
        IRegistryMetadata metadataProvider
    )
        PermissionedRegistry(datastore, metadataProvider, _msgSender(), 0)
        WrapperReceiver(nameWrapper, migratedRegistryFactory)
    {
        FALLBACK_RESOLVER = fallbackResolver;
        _disableInitializers();
    }

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(IERC165, WrapperReceiver, PermissionedRegistry) returns (bool) {
        return
            WrapperReceiver.supportsInterface(interfaceId) ||
            PermissionedRegistry.supportsInterface(interfaceId);
    }

    /// @inheritdoc IMigratedWrappedNameRegistry
    function initialize(
        IMigratedWrappedNameRegistry.ConstructorArgs calldata args
    ) public initializer {
        if (args.owner == address(0)) {
            revert CommonErrors.InvalidOwner();
        }

        // Set the parent domain for name resolution fallback
        parentNode = args.node;

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

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /// @inheritdoc IMigratedWrappedNameRegistry
    function parentName() external view returns (bytes memory) {
        return NAME_WRAPPER.names(parentNode);
    }

    function getResolver(
        string calldata label
    ) external view override(IRegistry, PermissionedRegistry) returns (address) {
        (, IRegistryDatastore.Entry memory entry) = getNameData(label);
        if (_isExpired(entry.expiry)) {
            return FALLBACK_RESOLVER; // unregistered children resolver in V1
        }
        return entry.resolver;
    }

    function _inject(TransferData memory td) internal override returns (uint256 tokenId) {
        return
            super._register(
                td.label,
                td.owner,
                IRegistry(td.subregistry),
                td.resolver,
                td.roleBitmap,
                td.expiry
            );
    }

    function _register(
        string memory label,
        address owner,
        IRegistry registry,
        address resolver,
        uint256 roleBitmap,
        uint64 expiry
    ) internal override returns (uint256 tokenId) {
        // If the name is emancipated (PARENT_CANNOT_CONTROL burned),
        // it must be migrated (owned by this registry)
        bytes32 node = NameCoder.namehash(parentNode, keccak256(bytes(label)));
        (, uint32 fuses, ) = NAME_WRAPPER.getData(uint256(node));
        if ((fuses & PARENT_CANNOT_CONTROL) != 0) {
            revert NameNotMigrated(NameCoder.addLabel(NAME_WRAPPER.names(parentNode), label));
        }
        return super._register(label, owner, registry, resolver, roleBitmap, expiry);
    }

    function _parentNode() internal view override returns (bytes32) {
        return parentNode;
    }

    function _registryImplementation() internal view override returns (address) {
        return ERC1967Utils.getImplementation();
    }
}
