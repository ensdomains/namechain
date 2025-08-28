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

    // Tracks which names are permanently locked
    mapping(uint256 => bool) private isLocked;

    constructor(
        IPermissionedRegistry _registry, 
        IBridge _bridge
    ) EjectionController(_registry, _bridge) {}

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
        bytes memory dnsEncodedName;
        (tokenId, dnsEncodedName) = _registerName(transferData, registry);
        emit NameEjectedToL1(dnsEncodedName, tokenId);
    }

    /**
     * @dev Handles migration of a locked .eth 2LD name.
     * Registers the name directly in the eth registry.
     *
     * @param transferData The transfer data for the name being migrated
     */
    function handleLockedNameMigration(
        TransferData memory transferData
    )
    external
    virtual
    onlyRootRoles(LibBridgeRoles.ROLE_EJECTOR)
    returns (uint256 tokenId)
    {
        bytes memory dnsEncodedName;
        (tokenId, dnsEncodedName) = _registerName(transferData, registry);
        
        // Prevent future ejections for this migrated name
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
    ) private returns (uint256 tokenId, bytes memory dnsEncodedName) {
        tokenId = targetRegistry.register(
            transferData.label,
            transferData.owner,
            IRegistry(transferData.subregistry),
            transferData.resolver,
            transferData.roleBitmap,
            transferData.expires
        );
        dnsEncodedName = NameUtils.dnsEncodeEthLabel(transferData.label);
    }

}
