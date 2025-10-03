// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {
    INameWrapper,
    CAN_EXTEND_EXPIRY,
    IS_DOT_ETH,
    CANNOT_UNWRAP
} from "@ens/contracts/wrapper/INameWrapper.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

import {UnauthorizedCaller} from "../common/Errors.sol";
import {IBridge} from "../common/IBridge.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {MigrationData} from "../common/TransferData.sol";
import {L1BridgeController} from "./L1BridgeController.sol";
import {LibLockedNames} from "./LibLockedNames.sol";
import {MigrationErrors} from "./MigrationErrors.sol";
import {IMigratedWrappedNameRegistry} from "../L1/IMigratedWrappedNameRegistry.sol";

contract L1LockedMigrationController is IERC1155Receiver, ERC165, Ownable {
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    IBaseRegistrar public immutable ETH_REGISTRY_V1;

    INameWrapper public immutable NAME_WRAPPER;

    L1BridgeController public immutable L1_BRIDGE_CONTROLLER;

    VerifiableFactory public immutable MIGRATED_REGISTRY_FACTORY;

    address public immutable MIGRATED_REGISTRY_IMPL;

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    error TokenIdMismatch(uint256 tokenId, uint256 expectedTokenId);

    error NodeMismatch(bytes32 tokenNode, bytes32 dataNode);

    ////////////////////////////////////////////////////////////////////////
    // Modifiers
    ////////////////////////////////////////////////////////////////////////

    modifier onlyCaller(address caller) {
        if (msg.sender != caller) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        IBaseRegistrar ethRegistryV1,
        INameWrapper nameWrapper,
        L1BridgeController l1BridgeController,
        VerifiableFactory migratedRegistryFactory,
        address migratedRegistryImpl
    ) Ownable(msg.sender) {
        ETH_REGISTRY_V1 = ethRegistryV1;
        NAME_WRAPPER = nameWrapper;
        L1_BRIDGE_CONTROLLER = l1BridgeController;
        MIGRATED_REGISTRY_FACTORY = migratedRegistryFactory;
        MIGRATED_REGISTRY_IMPL = migratedRegistryImpl;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
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
        uint256 id,
        uint256 /*amount*/,
        bytes calldata data
    ) external virtual onlyCaller(address(NAME_WRAPPER)) returns (bytes4) {
        _migrate(id, abi.decode(data, (MigrationData)));
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address /*operator*/,
        address /*from*/,
        uint256[] memory ids,
        uint256[] memory /*amounts*/,
        bytes calldata data
    ) external virtual onlyCaller(address(NAME_WRAPPER)) returns (bytes4) {
        MigrationData[] memory mds = abi.decode(data, (MigrationData[]));
        if (ids.length != mds.length) {
            revert IERC1155Errors.ERC1155InvalidArrayLength(ids.length, mds.length);
        }
        for (uint256 i; i < ids.length; ++i) {
            _migrate(ids[i], mds[i]);
        }
        return this.onERC1155BatchReceived.selector;
    }

    // md.toL1 ignored
    // md.transferData.name ignored
    // md.transferData.subregistry ignored
    // md.transferData.expiry ignored
    function _migrate(uint256 id, MigrationData memory md) internal {
        (address owner, uint32 fuses, uint64 expiry) = NAME_WRAPPER.getData(id);
        bytes memory name = NAME_WRAPPER.names(bytes32(id));

        if ((fuses & IS_DOT_ETH) == 0) {
            revert MigrationErrors.NameNotETH2LD(name);
        }
        if ((fuses & CANNOT_UNWRAP) == 0) {
            revert MigrationErrors.NameNotLocked(name);
        }

        // Determine permissions from name configuration (mask out CAN_EXTEND_EXPIRY to prevent automatic renewal for 2LDs)
        uint32 adjustedFuses = fuses & ~CAN_EXTEND_EXPIRY;
        (uint256 tokenRoles, uint256 subRegistryRoles) = LibLockedNames
            .generateRoleBitmapsFromFuses(adjustedFuses);

        // Create new registry instance for the migrated name
        address subregistry = MIGRATED_REGISTRY_FACTORY.deployProxy(
            MIGRATED_REGISTRY_IMPL,
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

        // Configure transfer data with registry and permission details
        if ((fuses & IS_DOT_ETH) != 0) {
            (bytes32 labelHash, ) = NameCoder.readLabel(name, 0);
            expiry = uint64(ETH_REGISTRY_V1.nameExpires(uint256(labelHash))); // vs. -= GRACE_PERIOD
        }

        md.transferData.name = name;
        md.transferData.expiry = expiry;
        md.transferData.subregistry = subregistry;
        md.transferData.roleBitmap = tokenRoles;

        // Process the locked name migration through bridge
        L1_BRIDGE_CONTROLLER.completeEjectionToL1(md.transferData);

        // Finalize migration by freezing the name
        LibLockedNames.freezeName(NAME_WRAPPER, id, fuses);
    }
}
