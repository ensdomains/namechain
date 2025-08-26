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

/**
 * @title L1BridgeController
 * @dev L1 contract for bridge controller that facilitates migrations of names
 * between L1 and L2, as well as handling renewals.
 */
contract L1BridgeController is EjectionController {
    error NotTokenOwner(uint256 tokenId);
    error NameNotExpired(uint256 tokenId, uint64 expires);
    error ParentNotMigrated(bytes name, uint256 offset);
    error InvalidOwner();
    error LockedNameCannotBeEjected(uint256 tokenId);
    error InvalidNameForMigration(bytes name);

    event RenewalSynchronized(uint256 tokenId, uint64 newExpiry);
    event LockedNameMigratedToL1(bytes name, uint256 tokenId);

    // Mapping to track locked names by tokenId
    mapping(uint256 => bool) private isLocked;
    
    // Root registry for handling TLD registrations
    IPermissionedRegistry public immutable rootRegistry;

    constructor(
        IPermissionedRegistry _registry, 
        IBridge _bridge,
        IPermissionedRegistry _rootRegistry
    ) EjectionController(_registry, _bridge) {
        rootRegistry = _rootRegistry;
    }

    /**
     * @dev Should be called when a name has been ejected from L2.  
     *
     * @param transferData The transfer data for the name being ejected
     */
    function completeEjectionFromL2(
        TransferData memory transferData
    ) 
    external 
    virtual 
    onlyRootRoles(LibBridgeRoles.ROLE_EJECTOR)
    returns (uint256 tokenId) 
    {
        tokenId = _registerName(transferData, registry);
        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(transferData.label);
        emit NameEjectedToL1(dnsEncodedName, tokenId);
    }

    /**
     * @dev Handles migration of a locked name by traversing the registry hierarchy.
     * Finds the parent registry and registers the name there.
     *
     * @param dnsEncodedName The DNS-encoded name of the full domain
     * @param transferData The transfer data for the name being migrated
     */
    function handleLockedNameMigration(
        bytes memory dnsEncodedName,
        TransferData memory transferData
    )
    external
    virtual
    onlyRootRoles(LibBridgeRoles.ROLE_EJECTOR)
    returns (uint256 tokenId)
    {
        // Find the parent registry for this name
        IRegistry parentRegistry = _findParentRegistryForMigration(dnsEncodedName, 0);
        
        // Register the name in the parent registry
        tokenId = _registerName(transferData, IPermissionedRegistry(address(parentRegistry)));
        
        // Mark this name as locked to prevent future ejections
        isLocked[tokenId] = true;
        
        emit LockedNameMigratedToL1(dnsEncodedName, tokenId);
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

            // check if this is a locked name that cannot be ejected
            if (isLocked[tokenId]) {
                revert LockedNameCannotBeEjected(tokenId);
            }

            // check that the owner is not null address
            if (transferData.owner == address(0)) {
                revert InvalidOwner();
            }

            // check that the label matches the token id
            _assertTokenIdMatchesLabel(tokenId, transferData.label);
            
            // burn the token
            registry.burn(tokenId);

            // send the message to the bridge
            bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(transferData.label);
            bridge.sendMessage(BridgeEncoder.encodeEjection(dnsEncodedName, transferData));
            emit NameEjectedToL2(dnsEncodedName, tokenId);
        }
    }

    /**
     * @dev Registers a name in the specified registry.
     *
     * @param transferData The transfer data for the name being registered
     * @param targetRegistry The registry to register the name in
     */
    function _registerName(
        TransferData memory transferData,
        IPermissionedRegistry targetRegistry
    ) private returns (uint256 tokenId) {
        tokenId = targetRegistry.register(
            transferData.label,
            transferData.owner,
            IRegistry(transferData.subregistry),
            transferData.resolver,
            transferData.roleBitmap,
            transferData.expires
        );
    }

    /**
     * @dev Finds the parent registry for a DNS-encoded domain name using pure recursion.
     * Handles any top-level domain (TLD) uniformly without special cases.
     * Returns the registry where the leftmost label should be registered.
     *
     * @param dnsEncodedName The DNS-encoded name (can be any TLD)
     * @param offset The current offset in the name
     */
    function _findParentRegistryForMigration(
        bytes memory dnsEncodedName,
        uint256 offset
    ) private view returns (IRegistry) {
        // Read the current label and next label
        (bytes32 labelHash, uint256 nextOffset) = NameCoder.readLabel(dnsEncodedName, offset);
        
        // If we're at the end (null terminator), this is invalid for migration
        if (labelHash == bytes32(0)) {
            revert InvalidNameForMigration(dnsEncodedName);
        }
        
        // If next label is null, current label is a TLD - return rootRegistry as parent
        if (dnsEncodedName[nextOffset] == 0) {
            return IRegistry(address(rootRegistry));
        }
        
        // Recursively find where the next part should be registered  
        IRegistry parentRegistry = _findParentRegistryForMigration(dnsEncodedName, nextOffset);
        
        // Extract the next label string from the DNS-encoded name
        (uint8 nextLabelLength, ) = NameCoder.nextLabel(dnsEncodedName, nextOffset);
        string memory nextLabel = new string(nextLabelLength);
        assembly {
            mcopy(add(nextLabel, 32), add(add(dnsEncodedName, 33), nextOffset), nextLabelLength)
        }
        
        // Get the subregistry for the next label from its parent
        IRegistry nextSubregistry = parentRegistry.getSubregistry(nextLabel);
        
        // If the subregistry doesn't exist, the parent hasn't been migrated yet
        if (address(nextSubregistry) == address(0)) {
            revert ParentNotMigrated(dnsEncodedName, nextOffset);
        }
        
        // Return the subregistry where the current label should be registered
        return nextSubregistry;
    }
}
