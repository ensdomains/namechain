// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {TransferData, MigrationData} from "../common/TransferData.sol";

import {IRegistry} from "../common/IRegistry.sol";
import {IRegistryDatastore} from "../common/IRegistryDatastore.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ITokenObserver} from "../common/ITokenObserver.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {EjectionController} from "../common/EjectionController.sol";
import {IBridge} from "../common/IBridge.sol";
import {BridgeEncoder} from "../common/BridgeEncoder.sol";
import {LibEACBaseRoles} from "../common/EnhancedAccessControl.sol";
import {IEnhancedAccessControl} from "../common/IEnhancedAccessControl.sol";
import {LibRegistryRoles} from "../common/LibRegistryRoles.sol";

/**
 * @title L2BridgeController
 * @dev Combined controller that handles both migration messages from L1 to L2 and ejection operations
 */
contract L2BridgeController is EjectionController, ITokenObserver {
    error MigrationFailed();
    error InvalidTLD(bytes dnsEncodedName);
    error NameNotFound(bytes dnsEncodedName);
    error NotTokenOwner(uint256 tokenId);
    error TooManyRoleAssignees(uint256 tokenId, uint256 roleBitmap);

    // Events
    event MigrationCompleted(bytes dnsEncodedName, uint256 newTokenId);

    bytes32 public constant ETH_TLD_HASH = keccak256(bytes("eth"));

    IRegistryDatastore public immutable datastore;

    constructor(
        IBridge _bridge,
        IPermissionedRegistry _registry, 
        IRegistryDatastore _datastore
    ) EjectionController(_registry, _bridge) {
        datastore = _datastore;
    }   

    /**
     * @dev Complete migration from L1 to L2
     * Called by the bridge when a migration message is received from L1
     * 
     * @param dnsEncodedName The DNS encoded name being migrated
     * @param migrationData The migration data containing transfer details
     */
    function completeMigrationFromL1(
        bytes memory dnsEncodedName,
        MigrationData memory migrationData
    ) external onlyBridge {
        // if migrating to L1 then there is nothing to do, else let's create a subregistry
        if (!migrationData.toL1) {
            // Find the token id and validate the registry tree
            uint256 tokenId = _findAndValidateLabelStructure(dnsEncodedName);

            // owner should be the bridge controller
            if (registry.ownerOf(tokenId) != address(this)) {
                revert NotTokenOwner(tokenId);
            }

            registry.setSubregistry(tokenId, IPermissionedRegistry(migrationData.transferData.subregistry));
            registry.setResolver(tokenId, migrationData.transferData.resolver);

            // now unset the token observer and transfer the name to the owner
            registry.setTokenObserver(tokenId, ITokenObserver(address(0)));
            registry.safeTransferFrom(address(this), migrationData.transferData.owner, tokenId, 1, "");

            emit MigrationCompleted(dnsEncodedName, tokenId);
        }
    }

    /**
     * @dev Should be called when a name is being ejected back to L2.
     *
     * @param transferData The transfer data for the name being migrated
     */
    function completeEjectionFromL1(
        TransferData memory transferData
    ) 
    external 
    virtual 
    onlyBridge 
    {
        (uint256 tokenId,,) = registry.getNameData(transferData.label);

        if (registry.ownerOf(tokenId) != address(this)) {
            revert NotTokenOwner(tokenId);
        }

        registry.setSubregistry(tokenId, IRegistry(transferData.subregistry));
        registry.setResolver(tokenId, transferData.resolver);
        registry.setTokenObserver(tokenId, ITokenObserver(address(0)));
        registry.safeTransferFrom(address(this), transferData.owner, tokenId, 1, "");

        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(transferData.label);
        emit NameEjectedToL2(dnsEncodedName, tokenId);
    }

    /**
     * @dev Override onERC1155Received to handle minting scenarios
     * When from is address(0), it's a mint operation and we should just return success
     * Otherwise, delegate to the parent implementation for ejection processing
     */
    function onERC1155Received(
        address /* operator */,
        address from,
        uint256 tokenId,
        uint256 /* amount */,
        bytes calldata data
    ) external virtual override onlyRegistry returns (bytes4) {
        // If from is not address(0), it's not a mint operation - process as ejection
        if (from != address(0)) {
            _processEjection(tokenId, data);
        }
        
        return this.onERC1155Received.selector;
    }

    /**
     * @dev Default implementation of onRenew that does nothing.
     * Can be overridden in derived contracts for custom behavior.
     */
    function onRenew(uint256 tokenId, uint64 expires, address /*renewedBy*/) external virtual {
        bridge.sendMessage(BridgeEncoder.encodeRenewal(tokenId, expires));
    }

    /**
     * @dev Validates 2LD structure and checks if label exists
     * @param name The DNS-encoded name (must be a 2LD like "example.eth")
     * @return tokenId The token id of the name
     */
    function _findAndValidateLabelStructure(
        bytes memory name
    ) internal view returns (uint256 tokenId) {
        // Read the second label which should be "eth"
        uint256 labelSize = uint8(name[0]);
        uint256 tldOffset = 1 + labelSize;
        uint256 tldSize = uint8(name[tldOffset]);
        
        // Verify the name is a .eth 2LD
        (bytes32 tldHash, ) = NameCoder.readLabel(name, tldOffset);
        if (tldHash != ETH_TLD_HASH || name[tldOffset + 1 + tldSize] != 0)) {
            revert InvalidTLD(name);
        }
        
        // Read the 2LD label
        string memory label = NameUtils.readLabel(name, 0);
        
        // Check if the label exists in the eth registry
        bool exists = address(registry.getSubregistry(label)) != address(0);
        if (!exists) {
            revert NameNotFound(name);
        }

        (tokenId, , ) = registry.getNameData(label);
        
        return tokenId;
    }

    /**
     * Overrides the EjectionController._onEject function.
     */
    function _onEject(uint256[] memory tokenIds, TransferData[] memory transferDataArray) internal virtual override {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            TransferData memory transferData = transferDataArray[i];

            // check that the label matches the token id
            _assertTokenIdMatchesLabel(tokenId, transferData.label);

            // check that there is no more than holder of the token observer and subregistry setting roles
            uint256 roleBitmap = LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY;
            (uint256 counts, uint256 mask) = IEnhancedAccessControl(address(registry)).getAssigneeCount(registry.getTokenIdResource(tokenId), roleBitmap);
            if (counts & mask != roleBitmap) {
                revert TooManyRoleAssignees(tokenId, roleBitmap);
            }

            // NOTE: we don't nullify the resolver here, so that there is no resolution downtime
            registry.setSubregistry(tokenId, IRegistry(address(0)));
            registry.setTokenObserver(tokenId, this);
            
            // Send bridge message for ejection
            bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(transferData.label);
            bridge.sendMessage(BridgeEncoder.encodeEjection(dnsEncodedName, transferData));
            emit NameEjectedToL1(dnsEncodedName, tokenId);
        }
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(EjectionController) returns (bool) {
        return interfaceId == type(ITokenObserver).interfaceId || super.supportsInterface(interfaceId);
    }
} 