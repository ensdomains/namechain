// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {TransferData, MigrationData} from "../common/TransferData.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title L2MigrationController
 * @dev Controller that handles migration messages from L1 to L2
 */
contract L2MigrationController is Ownable {
    error UnauthorizedCaller(address caller);
    error MigrationFailed();

    // Events
    event MigrationCompleted(bytes dnsEncodedName, MigrationData migrationData);

    address public immutable bridge;

    modifier onlyBridge() {
        if (msg.sender != bridge) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    constructor(address _bridge) Ownable(msg.sender) {
        bridge = _bridge;
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
        // TODO: Implement migration logic
        // - Validate the migration data
        //    - Check that the name is a .eth 2LD
        // - Check if the name is already registered on L2
        // - If it is, then revert
        // - Register the name on L2 registry and transfer ownership to the specified owner
        
        emit MigrationCompleted(dnsEncodedName, migrationData);
    }


} 