// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IPriceOracle} from "@ens/contracts/ethregistrar/IPriceOracle.sol";

/**
 * @dev Interface for token-based price oracles that extend IPriceOracle with ERC20 token support
 */
interface ITokenPriceOracle is IPriceOracle {
    struct TokenConfig {
        uint8 decimals;
        bool enabled;
    }

    error TokenNotSupported(address token);

    /**
     * @dev Get the configuration for a supported token
     * @param token The token address
     * @return The token configuration (check .enabled to see if supported)
     */
    function getTokenConfig(address token) external view returns (TokenConfig memory);

    /**
     * @dev Get the price for a name registration/renewal in a specific token
     * @param name The name being registered or renewed
     * @param expires When the name presently expires (0 if this is a new registration)
     * @param duration How long the name is being registered or extended for, in seconds
     * @param token The token address to get the price in
     * @return tokenAmount The amount of tokens required
     */
    function priceInToken(
        string calldata name,
        uint256 expires,
        uint256 duration,
        address token
    ) external view returns (uint256 tokenAmount);
}