// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IStandardRegistry} from "../common/IStandardRegistry.sol";
import {IRegistry} from "../common/IRegistry.sol";

/**
 * @title IL1ETHRegistry
 * @dev Interface for the L1 ETH registry.
 */
interface IL1ETHRegistry is IStandardRegistry {
    /**
     * @dev Receive an ejected name from Namechain.
     * @param tokenId The token ID of the name
     * @param owner The owner of the name
     * @param registry The registry to use for the name
     * @param resolver The resolver to use for the name
     * @param expires Expiration timestamp
     * @return tokenId The token ID of the ejected name
     */
    function ejectFromNamechain(uint256 tokenId, address owner, IRegistry registry, address resolver, uint64 expires) external returns (uint256);
}
