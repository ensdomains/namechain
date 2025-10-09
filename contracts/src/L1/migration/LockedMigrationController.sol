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
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {TransferData} from "../../common/bridge/types/TransferData.sol";
import {L1BridgeController} from "../bridge/L1BridgeController.sol";
import {IMigratedWrapperRegistry} from "../registry/interfaces/IMigratedWrapperRegistry.sol";
import {CommonErrors} from "../../common/CommonErrors.sol";
import {TransferErrors} from "../../common/TransferErrors.sol";
import {WrappedErrorLib} from "../../common/utils/WrappedErrorLib.sol";

import {LockedNamesLib} from "./libraries/LockedNamesLib.sol";

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

    uint256 private constant _DATA_SIZE = 128;

    bytes32 private constant _PAYLOAD_HASH = keccak256("LockedMigrationController");

    IBaseRegistrar public immutable ETH_REGISTRY_V1;

    INameWrapper public immutable NAME_WRAPPER;

    L1BridgeController public immutable L1_BRIDGE_CONTROLLER;

    VerifiableFactory public immutable MIGRATED_REGISTRY_FACTORY;

    address public immutable MIGRATED_REGISTRY_IMPL;

    ////////////////////////////////////////////////////////////////////////
    // Modifiers
    ////////////////////////////////////////////////////////////////////////

    modifier onlyNameWrapper() {
        if (msg.sender != address(NAME_WRAPPER)) {
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
        uint256 amount,
        bytes calldata data
    ) external onlyNameWrapper returns (bytes4) {
        if (data.length != _DATA_SIZE) {
            WrappedErrorLib.wrapAndRevert(
                abi.encodeWithSelector(TransferErrors.InvalidTransferData.selector)
            );
        }
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        Data[] memory mds = new Data[](1);
        ids[0] = id;
        amounts[0] = amount;
        mds[0] = abi.decode(data, (Data)); // reverts empty
        try this.finishERC1155Migration(ids, amounts, mds) {
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
        uint256[] calldata amounts,
        bytes calldata data
    ) external onlyNameWrapper returns (bytes4) {
        if (data.length != 64 + _DATA_SIZE * ids.length) {
            WrappedErrorLib.wrapAndRevert(
                abi.encodeWithSelector(TransferErrors.InvalidTransferData.selector)
            );
        }
        Data[] memory mds = abi.decode(data, (Data[]));
        try this.finishERC1155Migration(ids, amounts, mds) {
            // success
        } catch (bytes memory reason) {
            WrappedErrorLib.wrapAndRevert(reason);
        }
        return this.onERC1155BatchReceived.selector;
    }

    function finishERC1155Migration(
        uint256[] memory ids,
        uint256[] memory amounts,
        Data[] memory mds
    ) external {
        if (ids.length != amounts.length) {
            revert IERC1155Errors.ERC1155InvalidArrayLength(ids.length, amounts.length);
        }
        if (ids.length != mds.length) {
            revert IERC1155Errors.ERC1155InvalidArrayLength(ids.length, mds.length);
        }
        for (uint256 i; i < ids.length; ++i) {
            if (amounts[i] != 1) {
                revert TransferErrors.InvalidTransferAmount();
            }
            if (bytes32(ids[i]) != mds[i].node) {
                revert TransferErrors.NameWrapperTokenMismatch(ids[i], mds[i].node);
            }
        }
        for (uint256 i; i < mds.length; ++i) {
            Data memory md = mds[i];

            bytes memory name = NAME_WRAPPER.names(md.node);
            (, uint32 fuses, ) = NAME_WRAPPER.getData(uint256(md.node));

            if ((fuses & IS_DOT_ETH) == 0) {
                revert TransferErrors.NameNotETH2LD(name); // reverts if doesn't exist too
            }
            if ((fuses & CANNOT_UNWRAP) == 0) {
                revert TransferErrors.NameNotLocked(name);
            }

            // Determine permissions from name configuration (mask out CAN_EXTEND_EXPIRY to prevent automatic renewal for 2LDs)
            uint32 adjustedFuses = fuses & ~CAN_EXTEND_EXPIRY;
            (uint256 tokenRoles, uint256 subRegistryRoles) = LockedNamesLib
                .generateRoleBitmapsFromFuses(adjustedFuses);

            // configure transfer
            TransferData memory td;
            td.label = NameCoder.firstLabel(name); // safe by construction
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
            L1_BRIDGE_CONTROLLER.completeEjectionToL1(td);

            // Finalize migration by freezing the name
            LockedNamesLib.freezeName(NAME_WRAPPER, uint256(md.node), fuses);
        }
    }
}
