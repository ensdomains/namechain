// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ITokenObserver} from "../common/ITokenObserver.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {EjectionController} from "../common/EjectionController.sol";
import {TransferData} from "../common/TransferData.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {IRegistry} from "../common/IRegistry.sol";  
import {IBridge} from "../common/IBridge.sol";
import {BridgeEncoder} from "../common/BridgeEncoder.sol";
import {EnhancedAccessControl} from "../common/EnhancedAccessControl.sol";

/**
 * @title L2EjectionController
 * @dev L2 contract for ejection controller that facilitates migrations of names
 * between L1 and L2, as well as handling renewals.
 */
contract L2EjectionController is EjectionController, ITokenObserver, EnhancedAccessControl {
    error NotTokenOwner(uint256 tokenId);

    uint256 internal constant ROLE_MIGRATION_CONTROLLER = 1 << 0;
    uint256 internal constant ROLE_MIGRATION_CONTROLLER_ADMIN = ROLE_MIGRATION_CONTROLLER << 128;

    constructor(IPermissionedRegistry _registry, IBridge _bridge) EjectionController(_registry, _bridge) {
        _grantRoles(ROOT_RESOURCE, ROLE_MIGRATION_CONTROLLER_ADMIN, _msgSender(), false);
    }

    /**
     * @dev Default implementation of onRenew that does nothing.
     * Can be overridden in derived contracts for custom behavior.
     */
    function onRenew(uint256 /* tokenId */, uint64 /* expires */, address /* renewedBy */) external virtual {
        // Default implementation does nothing
    }

    /**
     * @dev Default implementation of onRelinquish that does nothing.
     * Can be overridden in derived contracts for custom behavior.
     */
    function onRelinquish(uint256 /* tokenId */, address /* relinquishedBy */) external virtual {
        // Default implementation does nothing
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
        registry.safeTransferFrom(address(this), transferData.owner, tokenId, 1, "");

        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(transferData.label);
        emit NameEjectedToL2(dnsEncodedName, tokenId);
    }

     function supportsInterface(bytes4 interfaceId) public view override(EjectionController, EnhancedAccessControl) returns (bool) {
        return interfaceId == type(ITokenObserver).interfaceId || super.supportsInterface(interfaceId);
    }

    // Internal functions

    /**
     * Overrides the EjectionController._onEject function.
     */
    function _onEject(address from, uint256[] memory tokenIds, TransferData[] memory transferDataArray) internal virtual override {
        uint256 tokenId;
        TransferData memory transferData;
        bool isMigrationTransfer = hasRoles(ROOT_RESOURCE, ROLE_MIGRATION_CONTROLLER, from);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenId = tokenIds[i];
            transferData = transferDataArray[i];

            // check that the label matches the token id
            _assertTokenIdMatchesLabel(tokenId, transferData.label);

            // NOTE: we don't nullify the resolver here, so that there is no resolution downtime
            registry.setSubregistry(tokenId, IRegistry(address(0)));

            // listen for events
            registry.setTokenObserver(tokenId, this);
            
            // Only send bridge message if this is not a migration transfer
            if (!isMigrationTransfer) {
                bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(transferDataArray[i].label);
                bridge.sendMessage(BridgeEncoder.encodeEjection(dnsEncodedName, transferDataArray[i]));
                emit NameEjectedToL1(dnsEncodedName, tokenId);
            }
        }
    }
}
