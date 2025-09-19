// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {TransferData} from "../common/TransferData.sol";
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
import {IBridge, LibBridgeRoles} from "../common/IBridge.sol";
import {BridgeEncoder} from "../common/BridgeEncoder.sol";
import {LibRegistryRoles} from "../common/LibRegistryRoles.sol";

/**
 * @title L2BridgeController
 * @dev Combined controller that handles both ejection messages from L1 to L2 and ejection operations
 */
contract L2BridgeController is EjectionController, ITokenObserver {
    error NotTokenOwner(uint256 tokenId);
    error TooManyRoleAssignees(uint256 tokenId, uint256 roleBitmap);

    IRegistryDatastore public immutable datastore;

    constructor(
        IBridge _bridge,
        IPermissionedRegistry _registry, 
        IRegistryDatastore _datastore
    ) EjectionController(_registry, _bridge) {
        datastore = _datastore;
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
    onlyRootRoles(LibBridgeRoles.ROLE_EJECTOR)
    {
        (uint256 tokenId,) = registry.getNameData(transferData.label);

        // owner should be the bridge controller
        if (registry.ownerOf(tokenId) != address(this)) {
            revert NotTokenOwner(tokenId);
        }

        registry.setSubregistry(tokenId, IRegistry(transferData.subregistry));
        registry.setResolver(tokenId, transferData.resolver);

        // now unset the token observer and transfer the name to the owner
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
    function onRenew(uint256 tokenId, uint64 expires, address /*renewedBy*/) external virtual onlyRegistry {
        bridge.sendMessage(BridgeEncoder.encodeRenewal(tokenId, expires));
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

            /*
            Check that there is no more than one holder of the token observer and subregistry setting roles.

            This works by calculating the no. of assignees for each of the given roles as a bitmap `(counts & mask)` where each role's corresponding 
            nybble is set to its assignee count.

            Since the roles themselves are bitmaps where each role's nybble is set to 1, we can simply comparing the two values to 
            check to see if each role has exactly one assignee.

            We also don't need to check that we (the bridge controller) are the sole assignee of these roles since we exercise these 
            roles further down below.
            */
            uint256 roleBitmap = 
                LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER |
                LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER_ADMIN |
                LibRegistryRoles.ROLE_SET_SUBREGISTRY |
                LibRegistryRoles.ROLE_SET_SUBREGISTRY_ADMIN;
            (uint256 counts, uint256 mask) = registry.getAssigneeCount(tokenId, roleBitmap);
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