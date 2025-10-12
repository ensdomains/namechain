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
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {TransferData} from "../../common/bridge/types/TransferData.sol";
import {CommonErrors} from "../../common/CommonErrors.sol";
import {TransferErrors} from "../../common/TransferErrors.sol";
import {WrappedErrorLib} from "../../common/utils/WrappedErrorLib.sol";
import {L1BridgeController} from "../bridge/L1BridgeController.sol";
import {
    IMigratedWrappedNameRegistry
} from "../registry/interfaces/IMigratedWrappedNameRegistry.sol";

import {LockedNamesLib} from "./libraries/LockedNamesLib.sol";

contract LockedMigrationController is IERC1155Receiver, ERC165, Ownable {
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    IBaseRegistrar public immutable ETH_REGISTRY_V1;

    INameWrapper public immutable NAME_WRAPPER;

    L1BridgeController public immutable L1_BRIDGE_CONTROLLER;

    VerifiableFactory public immutable MIGRATED_REGISTRY_FACTORY;

    address public immutable MIGRATED_REGISTRY_IMPL;

    ////////////////////////////////////////////////////////////////////////
    // Modifiers
    ////////////////////////////////////////////////////////////////////////

    modifier onlySender(address sender) {
        if (msg.sender != sender) {
            WrappedErrorLib.wrapAndRevert(
                abi.encodeWithSelector(CommonErrors.UnauthorizedCaller.selector, msg.sender)
            );
        }
        _;
    }

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

    function onERC1155Received(
        address /*operator*/,
        address /*from*/,
        uint256 id,
        uint256 /*amount*/,
        bytes calldata data
    ) external onlySender(address(NAME_WRAPPER)) returns (bytes4) {
        if (data.length != 128) {
            // abi.encode(Data).length
            WrappedErrorLib.wrapAndRevert(
                abi.encodeWithSelector(TransferErrors.InvalidTransferData.selector)
            );
        }
        uint256[] memory ids = new uint256[](1);
        IMigratedWrappedNameRegistry.Data[] memory mds = new IMigratedWrappedNameRegistry.Data[](1);
        ids[0] = id;
        mds[0] = abi.decode(data, (IMigratedWrappedNameRegistry.Data)); // reverts empty
        try this.finishERC1155Migration(ids, mds) {
            // success
        } catch (bytes memory reason) {
            WrappedErrorLib.wrapAndRevert(reason);
        }
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address /*operator*/,
        address /*from*/,
        uint256[] calldata ids,
        uint256[] calldata /*amounts*/,
        bytes calldata data
    ) external onlySender(address(NAME_WRAPPER)) returns (bytes4) {
        // never happens: caught by ERC1155Fuse
        // if (ids.length != amounts.length) {
        //     revert IERC1155Errors.ERC1155InvalidArrayLength(ids.length, amounts.length);
        // }
        if (data.length < 64) {
            WrappedErrorLib.wrapAndRevert(
                abi.encodeWithSelector(TransferErrors.InvalidTransferData.selector)
            );
        }
        IMigratedWrappedNameRegistry.Data[] memory mds = abi.decode(
            data,
            (IMigratedWrappedNameRegistry.Data[])
        ); // reverts empty
        try this.finishERC1155Migration(ids, mds) {
            // success
        } catch (bytes memory reason) {
            WrappedErrorLib.wrapAndRevert(reason);
        }
        return this.onERC1155BatchReceived.selector;
    }

    function finishERC1155Migration(
        uint256[] memory ids,
        IMigratedWrappedNameRegistry.Data[] memory mds
    ) external onlySender(address(this)) {
        if (ids.length != mds.length) {
            revert IERC1155Errors.ERC1155InvalidArrayLength(ids.length, mds.length);
        }
        for (uint256 i; i < ids.length; ++i) {
            // never happens: caught by ERC1155Fuse
            // https://github.com/ensdomains/ens-contracts/blob/staging/contracts/wrapper/ERC1155Fuse.sol#L182
            // https://github.com/ensdomains/ens-contracts/blob/staging/contracts/wrapper/ERC1155Fuse.sol#L293
            // if (amounts[i] != 1) {
            //     revert TransferErrors.InvalidTransferAmount();
            // }
            IMigratedWrappedNameRegistry.Data memory md = mds[i];
            if (bytes32(ids[i]) != md.node) {
                revert TransferErrors.TokenNodeMismatch(ids[i], mds[i].node);
            }
            if (md.owner == address(0)) {
                revert CommonErrors.InvalidOwner();
            }
        }
        for (uint256 i; i < mds.length; ++i) {
            IMigratedWrappedNameRegistry.Data memory md = mds[i];

            bytes memory name = NAME_WRAPPER.names(md.node);
            (, uint32 fuses, ) = NAME_WRAPPER.getData(uint256(md.node));
            // ignore owner, only we can call this function => we own it
            // ignore expiry, use underlying (see below)

            if ((fuses & IS_DOT_ETH) == 0) {
                revert TransferErrors.NameNotETH2LD(name); // reverts if doesn't exist too
            }
            if ((fuses & CANNOT_UNWRAP) == 0) {
                revert TransferErrors.NameNotLocked(name);
            }

            // PermissionedRegistry._register() => NameAlreadyRegistered
            // wont happen by construction

            // PermissionedRegistry._register() => CannotSetPastExpiration
            // wont happen as this operation is synchronous

            // PermissionedRegistry._register() => _grantRoles() => _checkRoleBitmap()
            // wont happen as roles are correct by construction

            // Determine permissions from name configuration (mask out CAN_EXTEND_EXPIRY to prevent automatic renewal for 2LDs)
            uint32 adjustedFuses = fuses & ~CAN_EXTEND_EXPIRY;
            (uint256 tokenRoles, uint256 subRegistryRoles) = LockedNamesLib
                .generateRoleBitmapsFromFuses(adjustedFuses);

            // configure transfer
            TransferData memory td;
            td.label = NameCoder.firstLabel(name); // safe by construction
            td.owner = md.owner;
            td.resolver = md.resolver;
            td.roleBitmap = tokenRoles; // safe by construction

            // create subregistry
            td.subregistry = MIGRATED_REGISTRY_FACTORY.deployProxy(
                MIGRATED_REGISTRY_IMPL,
                md.salt,
                abi.encodeCall(
                    IMigratedWrappedNameRegistry.initialize,
                    (
                        IMigratedWrappedNameRegistry.ConstructorArgs({
                            node: md.node, // safe by construction
                            owner: md.owner, // safe by construction
                            ownerRoles: subRegistryRoles, // safe by construction
                            registrar: address(0)
                        })
                    )
                )
            );

            // copy expiry
            (bytes32 labelHash, ) = NameCoder.readLabel(name, 0);
            td.expiry = uint64(ETH_REGISTRY_V1.nameExpires(uint256(labelHash))); // does not revert

            // Process the locked name migration through bridge
            L1_BRIDGE_CONTROLLER.completeEjectionToL1(td); // owner could reject transfer

            // Finalize migration by freezing the name
            LockedNamesLib.freezeName(NAME_WRAPPER, uint256(md.node), fuses); // will not revert (we own the token)
        }
    }
}
