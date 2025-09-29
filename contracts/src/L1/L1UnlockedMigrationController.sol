// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {INameWrapper, CANNOT_UNWRAP} from "@ens/contracts/wrapper/INameWrapper.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
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
    error TokenIdMismatch(uint256 tokenId, uint256 expectedTokenId);
    error MigrationNotSupported();

    IBaseRegistrar public immutable ethRegistryV1;
    INameWrapper public immutable nameWrapper;
    IBridge public immutable bridge;
    L1BridgeController public immutable l1BridgeController;

    uint256 private _unwrapGuard;

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

    /**
     * Implements ERC165.supportsInterface
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * Implements ERC1155Receiver.onERC1155Received
     */
    function onERC1155Received(
        address /*operator*/,
        address /*from*/,
        uint256 tokenId,
        uint256 /*amount*/,
        bytes calldata data
    ) external virtual returns (bytes4) {
        if (msg.sender != address(nameWrapper)) {
            revert UnauthorizedCaller(msg.sender);
        }

        MigrationData memory migrationData = abi.decode(data, (MigrationData));
        MigrationData[] memory migrationDataArray = new MigrationData[](1);
        migrationDataArray[0] = migrationData;

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        _migrateWrappedEthNames(tokenIds, migrationDataArray);

        return this.onERC1155Received.selector;
    }

    /**
     * Implements ERC1155Receiver.onERC1155BatchReceived
     */
    function onERC1155BatchReceived(
        address /*operator*/,
        address /*from*/,
        uint256[] memory tokenIds,
        uint256[] memory /*amounts*/,
        bytes calldata data
    ) external virtual returns (bytes4) {
        if (msg.sender != address(nameWrapper)) {
            revert UnauthorizedCaller(msg.sender);
        }

        MigrationData[] memory migrationDataArray = abi.decode(
            data,
            (MigrationData[])
        );

        _migrateWrappedEthNames(tokenIds, migrationDataArray);

        return this.onERC1155BatchReceived.selector;
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
    ) external virtual returns (bytes4) {
        if (msg.sender != address(ethRegistryV1)) {
            revert UnauthorizedCaller(msg.sender);
        }
        if (_unwrapGuard != tokenId) {
            MigrationData memory migrationData = abi.decode(
                data,
                (MigrationData)
            );
            _migrateNameViaBridge(tokenId, migrationData);
        }
        return this.onERC721Received.selector;
    }

    // Internal functions

    /**
     * @dev Called when wrapped .eth 2LD names are being migrated to v2.
     * Only supports unlocked names - reverts for locked names.
     *
     * @param tokenIds The token IDs of the .eth names.
     * @param migrationDataArray The migration data for each .eth name.
     */
    function _migrateWrappedEthNames(
        uint256[] memory tokenIds,
        MigrationData[] memory migrationDataArray
    ) internal {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            (, uint32 fuses, ) = nameWrapper.getData(tokenIds[i]);

            if (fuses & CANNOT_UNWRAP != 0) {
                // Name is locked
                revert MigrationNotSupported();
            }

            (bytes32 labelHash, ) = NameCoder.readLabel(
                nameWrapper.names(bytes32(tokenIds[i])),
                0
            );
   
            // Unwrap the unlocked name before migration
            // note: this will trigger a 721 transfer
            _unwrapGuard = uint256(labelHash);
            nameWrapper.unwrapETH2LD(labelHash, address(this), address(this));
            // Process migration via bridge
            _migrateNameViaBridge(uint256(labelHash), migrationDataArray[i]);
        }
        _unwrapGuard = 0;
    }

    /**
     * @dev Migrate a name via the bridge.
     *
     * @param tokenId The token ID of the .eth name.
     * @param migrationData The migration data.
     */
    function _migrateNameViaBridge(
        uint256 tokenId,
        MigrationData memory migrationData
    ) internal {
        // Validate that tokenId matches the label hash
        string memory label = NameUtils.extractLabel(
            migrationData.transferData.dnsEncodedName
        );
        uint256 expectedTokenId = uint256(keccak256(bytes(label)));
        if (tokenId != expectedTokenId) {
            revert TokenIdMismatch(tokenId, expectedTokenId);
        }

        // Handle L1 migration by setting up the name locally
        if (migrationData.toL1) {
            l1BridgeController.completeEjectionToL1(migrationData.transferData);
        }
        // Handle L2 migration by sending ejection message across bridge
        else {
            bytes memory message = BridgeEncoder.encodeEjection(
                migrationData.transferData
            );
            bridge.sendMessage(message);
        }
    }
}
