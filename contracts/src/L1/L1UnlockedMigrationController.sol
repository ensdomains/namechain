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
import {L1EjectionController} from "./L1EjectionController.sol";
import {NameUtils} from "../common/NameUtils.sol";

/**
 * @title L1UnlockedMigrationController
 * @dev Base contract for the v1-to-v2 migration controller that only handles unlocked .eth 2LD names.
 */
contract L1UnlockedMigrationController is IERC1155Receiver, IERC721Receiver, ERC165, Ownable {
    error UnauthorizedCaller(address caller);   
    error MigrationFailed();
    error TokenIdMismatch(uint256 tokenId, uint256 expectedTokenId);
    error MigrationNotSupported();

    IBaseRegistrar public immutable ethRegistryV1;
    INameWrapper public immutable nameWrapper;
    IBridge public immutable bridge;
    L1EjectionController public immutable l1EjectionController;

    constructor(IBaseRegistrar _ethRegistryV1, INameWrapper _nameWrapper, IBridge _bridge, L1EjectionController _l1EjectionController) Ownable(msg.sender) {
        ethRegistryV1 = _ethRegistryV1;
        nameWrapper = _nameWrapper;
        bridge = _bridge;
        l1EjectionController = _l1EjectionController;
    }

    /**
     * Implements ERC165.supportsInterface
     */
    function supportsInterface(bytes4 interfaceId) public virtual view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId
            || interfaceId == type(IERC721Receiver).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * Implements ERC1155Receiver.onERC1155Received
     */
    function onERC1155Received(address /*operator*/, address /*from*/, uint256 tokenId, uint256 /*amount*/, bytes calldata data) external virtual returns (bytes4) {
        if (msg.sender != address(nameWrapper)) {
            revert UnauthorizedCaller(msg.sender);
        }

        (MigrationData memory migrationData) = abi.decode(data, (MigrationData));
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
    function onERC1155BatchReceived(address /*operator*/, address /*from*/, uint256[] memory tokenIds, uint256[] memory /*amounts*/, bytes calldata data) external virtual returns (bytes4) {
        if (msg.sender != address(nameWrapper)) {
            revert UnauthorizedCaller(msg.sender);
        }

        (MigrationData[] memory migrationDataArray) = abi.decode(data, (MigrationData[]));

        _migrateWrappedEthNames(tokenIds, migrationDataArray);

        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @dev Implements ERC721Receiver.onERC721Received
     *
     * If this is called then it means an unwrapped .eth name is being migrated to v2.
     */
    function onERC721Received(address /*operator*/, address /*from*/, uint256 tokenId, bytes calldata data) external virtual returns (bytes4) {
        if (msg.sender != address(ethRegistryV1)) {
            revert UnauthorizedCaller(msg.sender);
        }
        
        (MigrationData memory migrationData) = abi.decode(data, (MigrationData));

        _migrateNameViaBridge(tokenId, migrationData);

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
    function _migrateWrappedEthNames(uint256[] memory tokenIds, MigrationData[] memory migrationDataArray) internal {                
        for (uint256 i = 0; i < tokenIds.length; i++) {
            (, uint32 fuses, ) = nameWrapper.getData(tokenIds[i]);
            
            if (fuses & CANNOT_UNWRAP != 0) { // Name is locked
                revert MigrationNotSupported();
            } else {
                // Name is unlocked, unwrap it first then migrate
                bytes32 labelHash = bytes32(tokenIds[i]);
                nameWrapper.unwrapETH2LD(labelHash, address(this), address(this));
                // now migrate
                _migrateNameViaBridge(tokenIds[i], migrationDataArray[i]);
            }
        }
    }

    /**
     * @dev Migrate a name via the bridge.
     *
     * @param tokenId The token ID of the .eth name.
     * @param migrationData The migration data.
     */
    function _migrateNameViaBridge(uint256 tokenId, MigrationData memory migrationData) internal {
        // Validate that tokenId matches the label hash
        uint256 expectedTokenId = uint256(keccak256(bytes(migrationData.transferData.label)));
        if (tokenId != expectedTokenId) {
            revert TokenIdMismatch(tokenId, expectedTokenId);
        }
        
        // send migration data to L2
        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(migrationData.transferData.label);
        bytes memory message = BridgeEncoder.encodeMigration(dnsEncodedName, migrationData);
        bridge.sendMessage(message);

        // if migrated to L1 then also setup the name on the L1
        if (migrationData.toL1) {
            l1EjectionController.completeEjectionFromL2(migrationData.transferData);
        }
    }
}
