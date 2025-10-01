// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {INameWrapper, CANNOT_UNWRAP} from "@ens/contracts/wrapper/INameWrapper.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {TransferData, MigrationData} from "../common/TransferData.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBridge} from "../common/IBridge.sol";
import {BridgeEncoder} from "../common/BridgeEncoder.sol";
import {L1BridgeController} from "./L1BridgeController.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import "../common/Errors.sol";

/// @dev The namehash of "eth".
bytes32 constant ETH_NODE = keccak256(abi.encode(bytes32(0), keccak256("eth")));

/**
 * @title L1UnlockedMigrationController
 * @dev Base contract for the v1-to-v2 migration controller that only handles unlocked .eth 2LD names.
 */
contract L1UnlockedMigrationController is
    IERC1155Receiver,
    IERC721Receiver,
    ERC165,
    Ownable
{
    error NodeMismatch(bytes32 tokenNode, bytes32 dataNode);
    error MigrationNotSupported();

    IBaseRegistrar public immutable ethRegistryV1;
    INameWrapper public immutable nameWrapper;
    IBridge public immutable bridge;
    L1BridgeController public immutable l1BridgeController;

    uint256 private _unwrappingTokenId;

    constructor(
        IBaseRegistrar _ethRegistryV1,
        INameWrapper _nameWrapper,
        L1BridgeController _l1BridgeController
    ) Ownable(msg.sender) {
        ethRegistryV1 = _ethRegistryV1;
        nameWrapper = _nameWrapper;
        bridge = _l1BridgeController.bridge();
        l1BridgeController = _l1BridgeController;
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

    modifier onlyCaller(address caller) {
        if (msg.sender != caller) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    /**
     * @dev Implements ERC721Receiver.onERC721Received
     *
     * If this is called then it means an unwrapped .eth name is being migrated to v2.
     */
    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 tokenId,
        bytes calldata data
    ) external virtual onlyCaller(address(ethRegistryV1)) returns (bytes4) {
        if (_unwrappingTokenId != tokenId) {
            MigrationData memory md = abi.decode(data, (MigrationData));
            bytes32 tokenNode = NameCoder.namehash(ETH_NODE, bytes32(tokenId));
            bytes32 dataNode = NameUtils.unhashedNamehash(
                md.transferData.dnsEncodedName,
                0
            );
            if (tokenNode != dataNode) {
                revert NodeMismatch(tokenNode, dataNode);
            }
            _migrate(md);
        }
        return this.onERC721Received.selector;
    }

    /// @inheritdoc IERC1155Receiver
    function onERC1155Received(
        address /*operator*/,
        address /*from*/,
        uint256 tokenId,
        uint256 /*amount*/,
        bytes calldata data
    ) external virtual onlyCaller(address(nameWrapper)) returns (bytes4) {
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        MigrationData[] memory mds = new MigrationData[](1);
        mds[0] = abi.decode(data, (MigrationData));
        _migrateWrappedEthNames(ids, mds);
        return this.onERC1155Received.selector;
    }

    /// @inheritdoc IERC1155Receiver
    function onERC1155BatchReceived(
        address /*operator*/,
        address /*from*/,
        uint256[] memory ids,
        uint256[] memory /*amounts*/,
        bytes calldata data
    ) external virtual onlyCaller(address(nameWrapper)) returns (bytes4) {
        MigrationData[] memory mds = abi.decode(data, (MigrationData[]));
        if (ids.length != mds.length) {
            revert IERC1155Errors.ERC1155InvalidArrayLength(
                ids.length,
                mds.length
            );
        }
        _migrateWrappedEthNames(ids, mds);
        return this.onERC1155BatchReceived.selector;
    }

    // Internal functions

    /// @dev Called when wrapped .eth 2LD names are being migrated to v2.
    /// Only supports unlocked names - reverts for locked names.
    /// Caller must check arrays are the same length.
    /// @param ids The token IDs of the .eth names.
    ///@param mds The migration data for each .eth name.
    function _migrateWrappedEthNames(
        uint256[] memory ids,
        MigrationData[] memory mds
    ) internal {
        for (uint256 i; i < ids.length; i++) {
            (, uint32 fuses, ) = nameWrapper.getData(ids[i]);
            if (fuses & CANNOT_UNWRAP != 0) {
                revert MigrationNotSupported(); // locked
            }
            bytes memory name = nameWrapper.names(bytes32(ids[i]));
            bytes32 tokenNode = NameUtils.unhashedNamehash(name, 0);
            bytes32 dataNode = NameUtils.unhashedNamehash(
                mds[i].transferData.dnsEncodedName,
                0
            );
            if (tokenNode != dataNode) {
                revert NodeMismatch(tokenNode, dataNode);
            }
            // assert ETH 2LD
            (bytes32 labelHash, ) = NameCoder.readLabel(name, 0);
            if (tokenNode != NameCoder.namehash(ETH_NODE, labelHash)) {
                revert MigrationNotSupported(); // not 2LD
            }
            // Unwrap the unlocked name before migration
            // note: this will trigger a 721 transfer
            _unwrappingTokenId = uint256(labelHash);
            nameWrapper.unwrapETH2LD(labelHash, address(this), address(this));
            _migrate(mds[i]);
        }
        _unwrappingTokenId = 0;
    }

    /// @dev Migrate a name via the bridge.
    /// @param md The migration data.
    function _migrate(MigrationData memory md) internal {
        if (md.toL1) {
            // Handle L1 migration by setting up the name locally
            l1BridgeController.completeEjectionToL1(md.transferData);
        } else {
            // Handle L2 migration by sending ejection message across bridge
            bridge.sendMessage(BridgeEncoder.encodeEjection(md.transferData));
        }
    }
}
