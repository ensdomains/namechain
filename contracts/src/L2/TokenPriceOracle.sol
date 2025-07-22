// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IPriceOracle} from "@ens/contracts/ethregistrar/IPriceOracle.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @dev TokenPriceOracle handles ERC20 token conversion rates with overridable pricing logic.
 * Inherits from this contract and override _premium() and _pricePerCharLength() for custom pricing.
 */
contract TokenPriceOracle is IPriceOracle {
    struct TokenConfig {
        uint8 decimals;
        bool enabled;
    }

    error TokenNotSupported(address token);
    error ArrayLengthMismatch();

    mapping(address => TokenConfig) public tokenConfigs;

    constructor(
        address[] memory _tokens, 
        uint8[] memory _decimals
    ) {
        if (_tokens.length != _decimals.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < _tokens.length; i++) {
            tokenConfigs[_tokens[i]] = TokenConfig({decimals: _decimals[i], enabled: true});
        }
    }

    function price(string calldata name, uint256 expires, uint256 duration)
        external
        view
        override
        returns (Price memory)
    {
        return Price({
            base: _pricePerCharLength(name, duration),
            premium: _premium(name, expires, duration)
        });
    }

    function isTokenSupported(address token) external view returns (bool) {
        return tokenConfigs[token].enabled;
    }

    function getTokenConfig(address token) external view returns (TokenConfig memory) {
        return tokenConfigs[token];
    }

    function priceInToken(string calldata name, uint256 expires, uint256 duration, address token)
        external
        view
        returns (uint256 tokenAmount)
    {
        TokenConfig memory config = tokenConfigs[token];
        if (!config.enabled) {
            revert TokenNotSupported(token);
        }

        Price memory usdPrice = this.price(name, expires, duration);
        uint256 totalUsdPrice = usdPrice.base + usdPrice.premium;

        // Convert USD price to token amount based on token's decimal standard
        // Prices are stored in 6 decimals (USDC standard)
        tokenAmount = _convertUsdToToken(totalUsdPrice, config.decimals);
    }

    /**
     * @dev Converts USD price (6 decimals) to token amount based on token decimals
     * @param usdAmount USD amount in 6 decimals
     * @param tokenDecimals Number of decimals for the target token
     * @return Token amount in the token's native decimals
     */
    function _convertUsdToToken(uint256 usdAmount, uint8 tokenDecimals) internal pure returns (uint256) {
        uint8 priceDecimals = 6; // USD prices stored in 6 decimals (USDC standard)
        
        if (tokenDecimals < priceDecimals) {
            return usdAmount / (10 ** (priceDecimals - tokenDecimals));
        } else if (tokenDecimals > priceDecimals) {
            return usdAmount * (10 ** (tokenDecimals - priceDecimals));
        } else {
            return usdAmount;
        }
    }


    /**
     * @dev Virtual function for calculating base price based on name characteristics
     * Override this function to implement custom pricing logic (e.g., length-based pricing)
     * @param name The name being priced
     * @param duration Duration of registration/renewal in seconds
     * @return Base price in USD with 6 decimals (USDC standard)
     */
    function _pricePerCharLength(string calldata name, uint256 duration) 
        internal 
        view 
        virtual 
        returns (uint256) 
    {
        // Default implementation: fixed base price
        return 10 * 1e6; // $10 in 6 decimals
    }

    /**
     * @dev Virtual function for calculating premium based on name expiry
     * Override this function to implement custom premium logic (e.g., exponential decay)
     * @param name The name being priced
     * @param expires When the name currently expires (0 for new registrations)
     * @param duration Duration of registration/renewal in seconds
     * @return Premium price in USD with 6 decimals (USDC standard)
     */
    function _premium(string calldata name, uint256 expires, uint256 duration) 
        internal 
        view 
        virtual 
        returns (uint256) 
    {
        // Default implementation: fixed premium
        return 5 * 1e6; // $5 in 6 decimals
    }

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IPriceOracle).interfaceId || 
               interfaceId == type(IERC165).interfaceId;
    }
}
