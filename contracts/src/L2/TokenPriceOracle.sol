// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IPriceOracle} from "@ens/contracts/ethregistrar/IPriceOracle.sol";

contract TokenPriceOracle is IPriceOracle {
    struct TokenConfig {
        uint8 decimals;
        bool enabled;
    }

    error TokenNotSupported(address token);
    error ArrayLengthMismatch();
    error InvalidPrice(uint256 price);

    mapping(address => TokenConfig) public tokenConfigs;
    uint256 public basePrice; // Base USD price in 6 decimals (USDC standard)
    uint256 public premiumPrice; // Premium USD price in 6 decimals

    constructor(address[] memory _tokens, uint8[] memory _decimals, uint256 _basePrice, uint256 _premiumPrice) {
        if (_tokens.length != _decimals.length) {
            revert ArrayLengthMismatch();
        }
        if (_basePrice == 0) {
            revert InvalidPrice(_basePrice);
        }
        if (_premiumPrice == 0) {
            revert InvalidPrice(_premiumPrice);
        }

        // Set configurable prices
        basePrice = _basePrice;
        premiumPrice = _premiumPrice;

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
        return Price(basePrice, premiumPrice);
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
        uint8 priceDecimals = 6;
        if (config.decimals < priceDecimals) {
            tokenAmount = totalUsdPrice / (10 ** (priceDecimals - config.decimals));
        } else if (config.decimals > priceDecimals) {
            tokenAmount = totalUsdPrice * (10 ** (config.decimals - priceDecimals));
        } else {
            tokenAmount = totalUsdPrice;
        }
    }
}
