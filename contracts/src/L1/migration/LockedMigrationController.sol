// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {
    INameWrapper,
    CAN_EXTEND_EXPIRY,
    IS_DOT_ETH,
    CANNOT_UNWRAP
} from "@ens/contracts/wrapper/INameWrapper.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {TransferData} from "../../common/bridge/types/TransferData.sol";
import {L1BridgeController} from "../bridge/L1BridgeController.sol";
import {IMigratedWrapperRegistry} from "../registry/interfaces/IMigratedWrapperRegistry.sol";

import {LockedNamesLib} from "./libraries/LockedNamesLib.sol";
import {MigrationErrors} from "./libraries/MigrationErrors.sol";

contract LockedMigrationController is IERC1155Receiver, ERC165, Ownable {
    ////////////////////////////////////////////////////////////////////////
    // Types
    ////////////////////////////////////////////////////////////////////////

    struct Data {
        bytes32 node;
        address owner;
        address resolver;
        uint256 salt;
    }

    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    bytes32 private constant _PAYLOAD_HASH = keccak256("LockedMigrationController");

    IBaseRegistrar public immutable ETH_REGISTRY_V1;

    INameWrapper public immutable NAME_WRAPPER;

    L1BridgeController public immutable L1_BRIDGE_CONTROLLER;

    VerifiableFactory public immutable MIGRATED_REGISTRY_FACTORY;

    address public immutable MIGRATED_REGISTRY_IMPL;

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        INameWrapper nameWrapper,
        L1BridgeController l1BridgeController,
        VerifiableFactory migratedRegistryFactory,
        address migratedRegistryImpl
    ) Ownable(msg.sender) {
        NAME_WRAPPER = nameWrapper;
        ETH_REGISTRY_V1 = IBaseRegistrar(nameWrapper.ens().owner(NameCoder.ETH_NODE));
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

    function migrate(Data calldata md) external returns (uint256 tokenId) {
        // acquire the token
        // reverts on approval, expired, dne
        NAME_WRAPPER.safeTransferFrom(
            msg.sender,
            address(this),
            uint256(md.node),
            1,
            abi.encode(_PAYLOAD_HASH)
        );
        tokenId = _finishMigration(md);
    }

    function migrate(Data[] calldata mds) external {
        uint256[] memory ids = new uint256[](mds.length);
        uint256[] memory amounts = new uint256[](mds.length);
        for (uint256 i; i < mds.length; ++i) {
            ids[i] = uint256(mds[i].node);
            amounts[i] = 1;
        }
        // acquire the tokens
        // reverts on approval, expired, dne
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
        return this.onERC1155Received.selector;
    }

    function _finishMigration(Data memory md) internal returns (uint256 tokenId) {
        bytes memory name = NAME_WRAPPER.names(md.node);
        (, uint32 fuses, ) = NAME_WRAPPER.getData(uint256(md.node));

        if ((fuses & IS_DOT_ETH) == 0) {
            revert MigrationErrors.NameNotETH2LD(name); // reverts if doesn't exist too
        }
        if ((fuses & CANNOT_UNWRAP) == 0) {
            revert MigrationErrors.NameNotLocked(name);
        }

        // Determine permissions from name configuration (mask out CAN_EXTEND_EXPIRY to prevent automatic renewal for 2LDs)
        uint32 adjustedFuses = fuses & ~CAN_EXTEND_EXPIRY;
        (uint256 tokenRoles, uint256 subRegistryRoles) = LockedNamesLib
            .generateRoleBitmapsFromFuses(adjustedFuses);

        // configure transfer
        TransferData memory td;
        td.label = NameCoder.firstLabel(name);
        td.owner = md.owner;
        td.resolver = md.resolver;
        td.roleBitmap = tokenRoles;

        // create subregistry
        td.subregistry = MIGRATED_REGISTRY_FACTORY.deployProxy(
            MIGRATED_REGISTRY_IMPL,
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
        );

        // copy expiry
        (bytes32 labelHash, ) = NameCoder.readLabel(name, 0);
        td.expiry = uint64(ETH_REGISTRY_V1.nameExpires(uint256(labelHash)));

        // Process the locked name migration through bridge
        tokenId = L1_BRIDGE_CONTROLLER.completeEjectionToL1(td);

        // Finalize migration by freezing the name
        LockedNamesLib.freezeName(NAME_WRAPPER, uint256(md.node), fuses);
    }
}
