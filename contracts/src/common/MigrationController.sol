// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {INameWrapper, CANNOT_UNWRAP} from "@ens/contracts/wrapper/INameWrapper.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IMigrationStrategy, MigrationData} from "./IMigration.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MigrationController
 * @dev Base contract for the v1-to-v2 migration controller.
 */
abstract contract MigrationController is IERC1155Receiver, IERC721Receiver, ERC165, Ownable {
    error CallerNotEthRegistryV1(address caller);   
    error NoMigrationStrategySet();
    error MigrationFailed();
    error NotOwner(uint256 tokenId);

    event StrategySet(IMigrationStrategy strategy);

    IBaseRegistrar public immutable ethRegistryV1;
    IMigrationStrategy public strategy;

    constructor(IBaseRegistrar _ethRegistryV1) Ownable(msg.sender) {
        ethRegistryV1 = _ethRegistryV1;
    }

    /**
     * @dev Sets the migration strategy.
     *
     * @param _strategy The migration strategy.
     */
    function setStrategy(IMigrationStrategy _strategy) external onlyOwner {
        strategy = _strategy;
        emit StrategySet(_strategy);
    }

    /**
     * Implements ERC165.supportsInterface
     */
    function supportsInterface(bytes4 interfaceId) public virtual view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(MigrationController).interfaceId || interfaceId == type(Ownable).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC721Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * Implements ERC1155Receiver.onERC1155Received
     */
    function onERC1155Received(address /*operator*/, address /*from*/, uint256 tokenId, uint256 /*amount*/, bytes calldata data) external virtual returns (bytes4) {
        (MigrationData memory migrationData) = abi.decode(data, (MigrationData));
        MigrationData[] memory migrationDataArray = new MigrationData[](1);
        migrationDataArray[0] = migrationData;

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        _migrateWrappedEthNames(msg.sender, tokenIds, migrationDataArray);
        
        return this.onERC1155Received.selector;
    }

    /**
     * Implements ERC1155Receiver.onERC1155BatchReceived
     */
    function onERC1155BatchReceived(address /*operator*/, address /*from*/, uint256[] memory tokenIds, uint256[] memory /*amounts*/, bytes calldata data) external virtual returns (bytes4) {
        (MigrationData[] memory migrationDataArray) = abi.decode(data, (MigrationData[]));

        _migrateWrappedEthNames(msg.sender, tokenIds, migrationDataArray);

        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @dev Implements ERC721Receiver.onERC721Received
     *
     * If this is called then it means an unwrapped .eth name is being migrated to v2.
     */
    function onERC721Received(address /*operator*/, address /*from*/, uint256 tokenId, bytes calldata data) external virtual returns (bytes4) {
        if (msg.sender != address(ethRegistryV1)) {
            revert CallerNotEthRegistryV1(msg.sender);
        }

        if (ethRegistryV1.ownerOf(tokenId) != address(this)) {
            revert NotOwner(tokenId);
        }
        
        (MigrationData memory migrationData) = abi.decode(data, (MigrationData));

        _migrateUnwrappedEthName(msg.sender, tokenId, migrationData);

        return this.onERC721Received.selector;
    }

    // Internal functions

    /**
     * @dev Called when wrapped .eth names are being migrated to v2.
     * Checks if names are locked (have CANNOT_UNWRAP burned) and routes accordingly.
     *
     * @param registry The address of the registry.
     * @param tokenIds The token IDs of the .eth names.
     * @param migrationDataArray The migration data for each .eth name.
     */
    function _migrateWrappedEthNames(address registry, uint256[] memory tokenIds, MigrationData[] memory migrationDataArray) internal {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            (, uint32 fuses, ) = INameWrapper(registry).getData(tokenIds[i]);
            
            if (fuses & CANNOT_UNWRAP != 0) { // Name is locked
                if (address(strategy) == address(0)) {
                    revert NoMigrationStrategySet();
                }
                // Name is locked, migrate through strategy
                strategy.migrateLockedEthName(registry, tokenIds[i], migrationDataArray[i]);
            } else {
                // Name is unlocked, migrate directly
                _migrateUnlockedEthName(registry, tokenIds[i], migrationDataArray[i]);
            }
        }
    }

    /**
     * @dev Called when an unwrapped .eth name is being migrated to v2.
     *
     * @param registry The address of the registry.
     * @param tokenId The token ID of the .eth name.
     * @param migrationData The migration data.
     */
    function _migrateUnwrappedEthName(address registry, uint256 tokenId, MigrationData memory migrationData) internal virtual;

    /**
     * @dev Called when an unlocked wrapped .eth name is being migrated to v2.
     *
     * @param registry The address of the registry.
     * @param tokenId The token ID of the .eth name.
     * @param migrationData The migration data.
     */
    function _migrateUnlockedEthName(address registry, uint256 tokenId, MigrationData memory migrationData) internal virtual;
}
