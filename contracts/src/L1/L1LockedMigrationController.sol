// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {INameWrapper, CAN_EXTEND_EXPIRY} from "@ens/contracts/wrapper/INameWrapper.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {UnauthorizedCaller} from "./../common/Errors.sol";
import {IBridge} from "./../common/IBridge.sol";
import {NameUtils} from "./../common/NameUtils.sol";
import {MigrationData} from "./../common/TransferData.sol";
import {L1BridgeController} from "./L1BridgeController.sol";
import {LibLockedNames} from "./LibLockedNames.sol";

/// @dev The namehash of "eth".
bytes32 constant ETH_NODE = keccak256(abi.encode(bytes32(0), keccak256("eth")));

contract L1LockedMigrationController is IERC1155Receiver, ERC165, Ownable {
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    IBaseRegistrar public immutable ETH_REGISTRY_V1;

    INameWrapper public immutable NAME_WRAPPER;

    IBridge public immutable BRIDGE;

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
        BRIDGE = l1BridgeController.BRIDGE();
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
        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        MigrationData[] memory mds = new MigrationData[](1);
        mds[0] = abi.decode(data, (MigrationData));
        _migrateLockedEthNames(ids, mds);
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
        _migrateLockedEthNames(ids, mds);
        return this.onERC1155BatchReceived.selector;
    }

    function _migrateLockedEthNames(uint256[] memory ids, MigrationData[] memory mds) internal {
        for (uint256 i; i < ids.length; ++i) {
            uint256 id = ids[i];
            MigrationData memory md = mds[i];

            (, uint32 fuses, ) = NAME_WRAPPER.getData(id);

            // Validate fuses and name type
            LibLockedNames.validateLockedName(fuses, id);
            LibLockedNames.validateIsDotEth2LD(fuses, id);

            // Determine permissions from name configuration (mask out CAN_EXTEND_EXPIRY to prevent automatic renewal for 2LDs)
            uint32 adjustedFuses = fuses & ~CAN_EXTEND_EXPIRY;
            (uint256 tokenRoles, uint256 subRegistryRoles) = LibLockedNames
                .generateRoleBitmapsFromFuses(adjustedFuses);

            // Create new registry instance for the migrated name
            address subregistry = LibLockedNames.deployMigratedRegistry(
                MIGRATED_REGISTRY_FACTORY,
                MIGRATED_REGISTRY_IMPL,
                md.transferData.owner,
                subRegistryRoles,
                md.salt,
                md.transferData.dnsEncodedName
            );

            // Configure transfer data with registry and permission details
            md.transferData.subregistry = subregistry;
            md.transferData.roleBitmap = tokenRoles;

            bytes memory name = NAME_WRAPPER.names(bytes32(id));
            bytes32 tokenNode = NameUtils.unhashedNamehash(name, 0);
            bytes32 dataNode = NameUtils.unhashedNamehash(md.transferData.dnsEncodedName, 0);
            if (tokenNode != dataNode) {
                revert NodeMismatch(tokenNode, dataNode);
            }

            // Process the locked name migration through bridge
            L1_BRIDGE_CONTROLLER.completeEjectionToL1(md.transferData);

            // Finalize migration by freezing the name
            LibLockedNames.freezeName(NAME_WRAPPER, id, fuses);
        }
    }
}
