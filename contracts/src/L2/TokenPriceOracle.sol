// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IPriceOracle} from "@ens/contracts/ethregistrar/IPriceOracle.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @dev TokenPriceOracle handles ERC20 token conversion rates with overridable pricing logic.
 * Inherits from this contract and override _premium() and _base() for custom pricing.
 */
contract TokenPriceOracle is IPriceOracle {
    struct TokenConfig {
        uint8 decimals;
        bool enabled;
    }

    error TokenNotSupported(address token);
    error ArrayLengthMismatch();
    error EmptyRentPrices();

    uint8 public constant USD_DECIMALS = 6; // USD prices stored in 6 decimals (USDC standard)
    
    mapping(address => TokenConfig) public tokenConfigs;
    uint256[] public rentPrices;

    constructor(
        address[] memory _tokens, 
        uint8[] memory _decimals,
        uint256[] memory _rentPrices
    ) {
        if (_tokens.length != _decimals.length) {
            revert ArrayLengthMismatch();
        }
        
        if (_rentPrices.length == 0) {
            revert EmptyRentPrices();
        }

        for (uint256 i = 0; i < _tokens.length; i++) {
            tokenConfigs[_tokens[i]] = TokenConfig({decimals: _decimals[i], enabled: true});
        }
        
        rentPrices = _rentPrices;
    }

    function price(string calldata name, uint256 expires, uint256 duration)
        external
        view
        override
        returns (Price memory)
    {
        return Price({
            base: _base(name, duration),
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
     * @dev Converts USD price (USD_DECIMALS) to token amount based on token decimals
     * @param usdAmount USD amount in USD_DECIMALS decimals
     * @param tokenDecimals Number of decimals for the target token
     * @return Token amount in the token's native decimals
     * @notice Rounds up for low-decimal tokens to prevent underpayment
     * @notice Includes overflow protection for high-decimal tokens
     */
    function _convertUsdToToken(uint256 usdAmount, uint8 tokenDecimals) internal pure returns (uint256) {
        uint8 priceDecimals = USD_DECIMALS; // USD prices stored in USD_DECIMALS (USDC standard)
        
        if (tokenDecimals < priceDecimals) {
            uint8 decimalDiff = priceDecimals - tokenDecimals;
            uint256 divisor = 10 ** decimalDiff;
            
            // For precision loss mitigation, round up if there's a remainder
            // This ensures users don't pay less than intended due to truncation
            uint256 quotient = usdAmount / divisor;
            uint256 remainder = usdAmount % divisor;
            
            // If there's any remainder, round up to prevent underpayment
            if (remainder > 0) {
                quotient += 1;
            }
            
            return quotient;
        } else if (tokenDecimals > priceDecimals) {
            uint8 decimalDiff = tokenDecimals - priceDecimals;
            
            // Check for overflow: if usdAmount * 10^decimalDiff > type(uint256).max
            // Rearranged: if usdAmount > type(uint256).max / 10^decimalDiff
            uint256 maxMultiplier = 10 ** decimalDiff;
            if (usdAmount > type(uint256).max / maxMultiplier) {
                revert("TokenPriceOracle: Amount too large for token decimals");
            }
            
            return usdAmount * maxMultiplier;
        } else {
            return usdAmount;
        }
    }


    /**
     * @dev Virtual function for calculating base price based on name characteristics
     * Override this function to implement custom pricing logic (e.g., length-based pricing)
     * @return Base price in USD with USD_DECIMALS decimals
     */
    function _base(string calldata /*name*/, uint256 /*duration*/) 
        internal 
        view 
        virtual 
        returns (uint256) 
    {
        // Default implementation: return first rent price
        // Note: rentPrices.length > 0 is guaranteed by constructor
        return rentPrices[0];
    }

    /**
     * @dev Virtual function for calculating premium based on name expiry
     * Override this function to implement custom premium logic (e.g., exponential decay)
     * @return Premium price in USD with USD_DECIMALS decimals
     */
    function _premium(string calldata /*name*/, uint256 /*expires*/, uint256 /*duration*/) 
        internal 
        view 
        virtual 
        returns (uint256) 
    {
        // Default implementation: no premium
        return 0; // $0 in USD_DECIMALS
    }


    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IPriceOracle).interfaceId || 
               interfaceId == type(IERC165).interfaceId;
    }
}
