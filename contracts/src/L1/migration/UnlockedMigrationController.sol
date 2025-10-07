// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {INameWrapper, CANNOT_UNWRAP} from "@ens/contracts/wrapper/INameWrapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {BridgeEncoderLib} from "../../common/bridge/libraries/BridgeEncoderLib.sol";
import {TransferData} from "../../common/bridge/types/TransferData.sol";
import {L1BridgeController} from "../bridge/L1BridgeController.sol";

import {MigrationErrors} from "./libraries/MigrationErrors.sol";

/// @dev Base contract for the v1-to-v2 migration controller that only handles unlocked .eth 2LD names.
contract UnlockedMigrationController is IERC1155Receiver, IERC721Receiver, ERC165, Ownable {
    ////////////////////////////////////////////////////////////////////////
    // Types
    ////////////////////////////////////////////////////////////////////////

    struct Data {
        bool toL1; // alternatives: toNamechain, stayOnMainnet, eject
        string label;
        address owner;
        address resolver;
        address subregistry;
        uint256 roleBitmap;
        uint256 salt;
    }

    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    bytes32 private constant _PAYLOAD_HASH = keccak256("UnlockedMigrationController");

    IBaseRegistrar public immutable ETH_REGISTRAR_V1;

    INameWrapper public immutable NAME_WRAPPER;

    L1BridgeController public immutable L1_BRIDGE_CONTROLLER;

    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    // TODO: remove this if we leave wrapped as-is
    uint256 private _ignoredTokenId;

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        INameWrapper nameWrapper,
        L1BridgeController l1BridgeController
    ) Ownable(msg.sender) {
        NAME_WRAPPER = nameWrapper;
        ETH_REGISTRAR_V1 = IBaseRegistrar(nameWrapper.ens().owner(NameCoder.ETH_NODE));
        L1_BRIDGE_CONTROLLER = l1BridgeController;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /// @inheritdoc IERC721Receiver
    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        require(msg.sender == address(ETH_REGISTRAR_V1), MigrationErrors.ERROR_ONLY_ETH_REGISTRAR);
        if (bytes32(data) != _PAYLOAD_HASH) {
            require(_ignoredTokenId == tokenId, MigrationErrors.ERROR_UNEXPECTED_TRANSFER);
            _ignoredTokenId = 0;
        }
        return this.onERC721Received.selector;
    }

    /// @dev Migrate a single unwrapped or wrapped token with approval.
    function migrate(Data calldata md) external {
        Data[] memory mds = new Data[](1);
        mds[0] = md;
        _migrate(mds);
    }

    /// @dev Migrate multiple unwrapped or wrapped tokens with approval.
    function migrate(Data[] calldata mds) external {
        _migrate(mds);
    }

    /// @inheritdoc IERC1155Receiver
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

    /// @inheritdoc IERC1155Receiver
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

    function _migrate(Data[] memory mds) internal {
        uint256 wrapped;
        uint256[] memory ids = new uint256[](mds.length);
        for (uint256 i; i < mds.length; ++i) {
            Data memory md = mds[i];
            bytes32 labelHash = keccak256(bytes(md.label));
            if (NAME_WRAPPER.isWrapped(NameCoder.ETH_NODE, labelHash)) {
                uint256 id = uint256(NameCoder.namehash(NameCoder.ETH_NODE, labelHash));
                // by construction, this is already .eth
                (, uint32 fuses, ) = NAME_WRAPPER.getData(id);
                if ((fuses & CANNOT_UNWRAP) != 0) {
                    revert MigrationErrors.NameIsLocked(NameCoder.ethName(md.label));
                }
                mds[wrapped] = md; // reorder
                ids[wrapped++] = id;
            } else {
                // TODO: this could have typed errors
                // - doesn't exist
                // - not approved
                ETH_REGISTRAR_V1.safeTransferFrom(
                    msg.sender,
                    address(this),
                    uint256(labelHash),
                    abi.encode(_PAYLOAD_HASH)
                );
                _finishMigration(md);
            }
        }
        if (wrapped == 1) {
            NAME_WRAPPER.safeTransferFrom(
                msg.sender,
                address(this),
                ids[0],
                1,
                abi.encode(_PAYLOAD_HASH)
            );
        } else if (wrapped > 1) {
            assembly {
                mstore(ids, wrapped) // truncate
            }
            uint256[] memory amounts = new uint256[](wrapped);
            for (uint256 i; i < wrapped; ++i) {
                amounts[i] = 1;
            }
            NAME_WRAPPER.safeBatchTransferFrom(
                msg.sender,
                address(this),
                ids,
                amounts,
                abi.encode(_PAYLOAD_HASH)
            );
        }
        for (uint256 i; i < wrapped; ++i) {
            bytes32 labelHash = keccak256(bytes(mds[i].label));
            _ignoredTokenId = uint256(labelHash); // since we cannot add a payload
            NAME_WRAPPER.unwrapETH2LD(labelHash, address(this), address(this));
        }
        for (uint256 i; i < wrapped; ++i) {
            _finishMigration(mds[i]);
        }
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    /// @dev Migrate V1 `{label}.eth` to V2 mainnet or Namechain.
    /// @param md The migration data.
    function _finishMigration(Data memory md) internal {
        TransferData memory td = TransferData({
            label: md.label,
            owner: md.owner,
            resolver: md.resolver,
            subregistry: md.subregistry,
            roleBitmap: md.roleBitmap,
            expiry: md.toL1
                ? uint64(ETH_REGISTRAR_V1.nameExpires(uint256(keccak256(bytes(md.label)))))
                : 0
        });
        if (md.toL1) {
            L1_BRIDGE_CONTROLLER.completeEjectionToL1(td);
        } else {
            L1_BRIDGE_CONTROLLER.BRIDGE().sendMessage(BridgeEncoderLib.encodeEjection(td));
        }
    }
}
