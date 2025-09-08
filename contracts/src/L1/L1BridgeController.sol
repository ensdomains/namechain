// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {EjectionController} from "../common/EjectionController.sol";
import {TransferData} from "../common/TransferData.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {LibRegistryRoles} from "../common/LibRegistryRoles.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {IBridge, LibBridgeRoles} from "../common/IBridge.sol";
import {BridgeEncoder} from "../common/BridgeEncoder.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import "../common/Errors.sol";

/**
 * @title L1BridgeController
 * @dev L1 contract for bridge controller that facilitates migrations of names
 * between L1 and L2, as well as handling renewals.
 */
contract L1BridgeController is EjectionController {
    error NotTokenOwner(uint256 tokenId);
    error LockedNameCannotBeEjected(uint256 tokenId);

    event RenewalSynchronized(uint256 tokenId, uint64 newExpiry);


    constructor(
        IPermissionedRegistry _registry, 
        IBridge _bridge
    ) EjectionController(_registry, _bridge) {}

    /**
     * @dev Should be called when a name is being ejected to L1.  
     *
     * @param transferData The transfer data for the name being ejected
     */
    function completeEjectionToL1(
        TransferData memory transferData
    ) 
    external 
    virtual 
    onlyRootRoles(LibBridgeRoles.ROLE_EJECTOR)
    returns (uint256 tokenId) 
    {
        string memory label = NameUtils.extractLabel(transferData.dnsEncodedName);
        
        tokenId = registry.register(
            label,
            transferData.owner,
            IRegistry(transferData.subregistry),
            transferData.resolver,
            transferData.roleBitmap,
            transferData.expires
        );
        emit NameEjectedToL1(transferData.dnsEncodedName, tokenId);
    }


    /**
     * @dev Sync the renewal of a name with the L2 registry.
     *
     * @param tokenId The token ID of the name
     * @param newExpiry The new expiration timestamp
     */
    function syncRenewal(uint256 tokenId, uint64 newExpiry) external virtual onlyRootRoles(LibBridgeRoles.ROLE_EJECTOR) {
        registry.renew(tokenId, newExpiry);
        emit RenewalSynchronized(tokenId, newExpiry);
    }

    // Internal functions

    /**
     * Overrides the EjectionController._onEject function.
     */
    function _onEject(uint256[] memory tokenIds, TransferData[] memory transferDataArray) internal override virtual {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            TransferData memory transferData = transferDataArray[i];

            // Check if name is locked (no assignees for ROLE_SET_SUBREGISTRY or ROLE_SET_SUBREGISTRY_ADMIN means locked)
            uint256 resource = NameUtils.getCanonicalId(tokenId);
            (uint256 count, ) = registry.getAssigneeCount(resource, LibRegistryRoles.ROLE_SET_SUBREGISTRY | LibRegistryRoles.ROLE_SET_SUBREGISTRY_ADMIN);
            if (count == 0) {
                revert LockedNameCannotBeEjected(tokenId);
            }

            // check that the owner is not null address
            if (transferData.owner == address(0)) {
                revert InvalidOwner();
            }

            // check that the label matches the token id
            _assertTokenIdMatchesLabel(tokenId, transferData.dnsEncodedName);
            
            // burn the token
            registry.burn(tokenId);

            // send the message to the bridge
            bridge.sendMessage(BridgeEncoder.encodeEjection(transferData));
            emit NameEjectedToL2(transferData.dnsEncodedName, tokenId);
        }
    }


}
