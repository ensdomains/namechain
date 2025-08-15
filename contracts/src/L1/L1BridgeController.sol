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
    error ParentNotMigrated(bytes dnsEncodedName, uint256 offset);

    event RenewalSynchronized(uint256 tokenId, uint64 newExpiry);

    constructor(IPermissionedRegistry _registry, IBridge _bridge) EjectionController(_registry, _bridge) {}

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
        emit NameEjectedToL1(dnsEncodedName, tokenId);
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

    // Private functions

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
     * @dev Finds the parent registry for a DNS-encoded name by traversing the hierarchy.
     * For a name like "sub.parent", this will:
     * 1. Find "parent" in root registry
     * 2. Return parent's registry so "sub" can be registered there
     * Reverts if any parent component is not found in the registry.
     *
     * @param dnsEncodedName The DNS-encoded name
     * @param offset The current offset in the name
     */
    function _findParentRegistryForMigration(
        bytes memory dnsEncodedName,
        uint256 offset
    ) private view returns (IRegistry) {
        // Read the current label (e.g., "sub" in "sub.parent")
        (bytes32 labelHash, uint256 nextOffset) = NameCoder.readLabel(dnsEncodedName, offset);
        
        // If we're at the end (null terminator), something is wrong
        if (labelHash == bytes32(0)) {
            return IRegistry(address(registry));
        }
        
        // Check if there's another label after this one
        (bytes32 nextLabelHash, ) = NameCoder.readLabel(dnsEncodedName, nextOffset);
        
        // If the next label is the null terminator, this is a 2LD
        // The parent is the root registry
        if (nextLabelHash == bytes32(0)) {
            return IRegistry(address(registry));
        }
        
        // Otherwise, we have a subdomain (3LD or deeper)
        // We need to find where the parent is registered
        // For "sub.parent", we need to find "parent" first
        IRegistry parentOfParentRegistry = _findParentRegistryForMigration(dnsEncodedName, nextOffset);
        
        // Now get the parent's label and check if it exists
        string memory parentLabel = _readLabel(dnsEncodedName, nextOffset);
        IRegistry parentSubregistry = parentOfParentRegistry.getSubregistry(parentLabel);
        
        // If the parent's subregistry doesn't exist, the parent hasn't been migrated yet
        if (address(parentSubregistry) == address(0)) {
            revert ParentNotMigrated(dnsEncodedName, nextOffset);
        }
        
        // Return the parent's registry where the current label should be registered
        return parentSubregistry;
    }

    /**
     * @dev Reads a label from a DNS-encoded name at the specified offset.
     *
     * @param name The DNS-encoded name
     * @param offset The offset to read from
     */
    function _readLabel(
        bytes memory name,
        uint256 offset
    ) private pure returns (string memory label) {
        (uint8 size, ) = NameCoder.nextLabel(name, offset);
        label = new string(size);
        assembly {
            mcopy(add(label, 32), add(add(name, 33), offset), size)
        }
    }

    // Internal functions

    /**
     * Overrides the EjectionController._onEject function.
     */
    function _onEject(uint256[] memory tokenIds, TransferData[] memory transferDataArray) internal override virtual {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            TransferData memory transferData = transferDataArray[i];

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
}
