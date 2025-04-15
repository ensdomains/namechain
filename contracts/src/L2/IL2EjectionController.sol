// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ITokenObserver} from "../common/ITokenObserver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/**
 * @title IL1EjectionController
 * @dev Interface for the L1 ejection controller that facilitates migrations of names
 * between L1 and L2, as well as handling renewals. The controller is responsible
 * for cross-chain communication.
 */
interface IL2EjectionController is ITokenObserver, IERC1155Receiver {
    /**
     * @dev Called the L2ETHRegistry when a user ejects a name to L1.
     *
     * @param tokenId The token ID of the name being ejected
     * @param l1Owner The address that will own the name on L1
     * @param l1Subregistry The subregistry address to use on L1    
     */
    function ejectToL1(uint256 tokenId, address l1Owner, address l1Subregistry) external;

    /**
     * @dev Called by the cross-chain messaging system when a name is being migrated back to L2.
     *
     * @param labelHash The keccak256 hash of the label
     * @param l2Owner The address that will own the name on L2
     * @param l2Subregistry The subregistry address to use on L2
     */
    function completeMigrationToL2(
        uint256 labelHash,
        address l2Owner,
        address l2Subregistry
    ) external;
}
