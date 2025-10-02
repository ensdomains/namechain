// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {INameWrapper, CANNOT_UNWRAP} from "@ens/contracts/wrapper/INameWrapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {BridgeEncoder} from "./../common/BridgeEncoder.sol";
import {UnauthorizedCaller} from "./../common/Errors.sol";
import {IBridge} from "./../common/IBridge.sol";
import {NameUtils} from "./../common/NameUtils.sol";
import {MigrationData} from "./../common/TransferData.sol";
import {L1BridgeController} from "./L1BridgeController.sol";

/// @dev The namehash of "eth".
bytes32 constant ETH_NODE = keccak256(abi.encode(bytes32(0), keccak256("eth")));

/// @dev Base contract for the v1-to-v2 migration controller that only handles unlocked .eth 2LD names.
contract L1UnlockedMigrationController is IERC1155Receiver, IERC721Receiver, ERC165, Ownable {
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    string public constant ERROR_NODE_MISMATCH =
        "L1UnlockedMigrationController: name and MigrationData mismatch";

    string public constant ERROR_NAME_IS_LOCKED = "L1UnlockedMigrationController: name is locked";

    string public constant ERROR_NAME_NOT_ETH2LD = "L1UnlockedMigrationController: not {label}.eth";

    IBaseRegistrar public immutable ETH_REGISTRY_V1;

    INameWrapper public immutable NAME_WRAPPER;

    IBridge public immutable BRIDGE;

    L1BridgeController public immutable L1_BRIDGE_CONTROLLER;

    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    uint256 private _ignoredTokenId;

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    error NodeMismatch(bytes32 tokenNode, bytes32 transferNode);
    error NameIsLocked(bytes name);
    error NameNotETH2LD(bytes name);

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
        L1BridgeController l1BridgeController
    ) Ownable(msg.sender) {
        ETH_REGISTRY_V1 = ethRegistryV1;
        NAME_WRAPPER = nameWrapper;
        BRIDGE = l1BridgeController.BRIDGE();
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

    /// @dev Migrate multiple unwrapped or wrapped tokens with approval.
    function migrateETH2LD(MigrationData[] memory mds) public {
        for (uint256 i; i < mds.length; i++) {
            MigrationData memory md = mds[i];
            bytes32 node = NameUtils.unhashedNamehash(md.transferData.dnsEncodedName, 0);
            if (node != bytes32(0) && NAME_WRAPPER.isWrapped(node)) {
                uint256 tokenId = uint256(node);
                _ignoredTokenId = tokenId;
                NAME_WRAPPER.safeTransferFrom(msg.sender, address(this), tokenId, 1, "");
                _ignoredTokenId = 0;
                _migrateWrapped(tokenId, md, false);
            } else {
                (bytes32 labelHash, ) = NameCoder.readLabel(md.transferData.dnsEncodedName, 0);
                uint256 tokenId = uint256(labelHash);
                _ignoredTokenId = tokenId;
                ETH_REGISTRY_V1.safeTransferFrom(msg.sender, address(this), tokenId, "");
                _ignoredTokenId = 0;
                _migrateUnwrapped(tokenId, md, false);
            }
        }
    }

    /// @dev Migrate a single unwrapped or wrapped token with approval.
    function migrateETH2LD(MigrationData calldata md) external {
        MigrationData[] memory mds = new MigrationData[](1);
        mds[0] = md;
        migrateETH2LD(mds);
    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 tokenId,
        bytes calldata data
    ) external virtual onlyCaller(address(ETH_REGISTRY_V1)) returns (bytes4) {
        if (_ignoredTokenId != tokenId) {
            _migrateUnwrapped(tokenId, abi.decode(data, (MigrationData)), true);
        }
        return this.onERC721Received.selector;
    }

    /// @inheritdoc IERC1155Receiver
    function onERC1155Received(
        address /*operator*/,
        address /*from*/,
        uint256 id,
        uint256 /*amount*/,
        bytes calldata data
    ) external virtual onlyCaller(address(NAME_WRAPPER)) returns (bytes4) {
        if (_ignoredTokenId != id) {
            _migrateWrapped(id, abi.decode(data, (MigrationData)), true);
        }
        return this.onERC1155Received.selector;
    }

    /// @inheritdoc IERC1155Receiver
    function onERC1155BatchReceived(
        address /*operator*/,
        address /*from*/,
        uint256[] calldata ids,
        uint256[] calldata /*amounts*/,
        bytes calldata data
    ) external virtual onlyCaller(address(NAME_WRAPPER)) returns (bytes4) {
        MigrationData[] memory mds = abi.decode(data, (MigrationData[]));
        if (ids.length != mds.length) {
            revert IERC1155Errors.ERC1155InvalidArrayLength(ids.length, mds.length);
        }
        for (uint256 i; i < ids.length; i++) {
            _migrateWrapped(ids[i], mds[i], true);
        }
        return this.onERC1155BatchReceived.selector;
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    function _migrateUnwrapped(
        uint256 tokenId,
        MigrationData memory md,
        bool viaReceiver
    ) internal {
        _assertNodes(
            NameCoder.namehash(ETH_NODE, bytes32(tokenId)),
            NameUtils.unhashedNamehash(md.transferData.dnsEncodedName, 0),
            viaReceiver
        );
        _migrate(tokenId, md);
    }

    /// @dev Migrate a wrapped name.
    /// @param id The wrapped token.
    /// @param md The migration data.
    /// @param viaReceiver The migration occurred via IERC1155Receiver.
    function _migrateWrapped(uint256 id, MigrationData memory md, bool viaReceiver) internal {
        bytes memory name = NAME_WRAPPER.names(bytes32(id));
        bytes32 node = NameUtils.unhashedNamehash(name, 0);
        (, uint32 fuses, ) = NAME_WRAPPER.getData(id);
        if (fuses & CANNOT_UNWRAP != 0) {
            if (viaReceiver) {
                revert(ERROR_NAME_IS_LOCKED);
            } else {
                revert NameIsLocked(name);
            }
        }
        bytes32 labelHash;
        if (name.length > 0) {
            (labelHash, ) = NameCoder.readLabel(name, 0);
        }
        if (node != NameCoder.namehash(ETH_NODE, labelHash)) {
            if (viaReceiver) {
                revert(ERROR_NAME_NOT_ETH2LD);
            } else {
                revert NameNotETH2LD(name);
            }
        }
        _assertNodes(
            node,
            NameUtils.unhashedNamehash(md.transferData.dnsEncodedName, 0),
            viaReceiver
        );
        _ignoredTokenId = uint256(labelHash);
        NAME_WRAPPER.unwrapETH2LD(labelHash, address(this), address(this));
        _ignoredTokenId = 0;
        _migrate(uint256(labelHash), md);
    }

    function _assertNodes(bytes32 tokenNode, bytes32 transferNode, bool viaReceiver) internal pure {
        if (tokenNode != transferNode) {
            if (viaReceiver) {
                revert(ERROR_NODE_MISMATCH);
            } else {
                revert NodeMismatch(tokenNode, transferNode);
            }
        }
    }

    /// @dev Migrate a name locally or via the bridge.
    /// @param tokenId The labelhash.
    /// @param md The migration data.
    function _migrate(uint256 tokenId, MigrationData memory md) internal {
        if (md.toL1) {
            // sync actual expiration
            md.transferData.expires = uint64(ETH_REGISTRY_V1.nameExpires(tokenId));
            // Handle L1 migration by setting up the name locally
            L1_BRIDGE_CONTROLLER.completeEjectionToL1(md.transferData);
        } else {
            // Handle L2 migration by sending ejection message across BRIDGE
            BRIDGE.sendMessage(BridgeEncoder.encodeEjection(md.transferData));
        }
    }
}
