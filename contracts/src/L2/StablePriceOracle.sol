// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "./TokenPriceOracle.sol";

contract StablePriceOracle is TokenPriceOracle {
    error InvalidRentPricesLength();

    constructor(
        address[] memory _tokens,
        uint8[] memory _decimals,
        uint256[] memory _rentPrices
    ) TokenPriceOracle(_tokens, _decimals, _rentPrices) {
        if (_rentPrices.length != 5) {
            revert InvalidRentPricesLength();
        }
    }

    function _base(string calldata name, uint256 duration) 
        internal 
        view 
        virtual 
        override 
        returns (uint256) 
    {
        uint256 len = bytes(name).length;
        uint256 basePrice;

        if (len >= 5) {
            basePrice = rentPrices[0] * duration;
        } else if (len == 4) {
            basePrice = rentPrices[1] * duration;
        } else if (len == 3) {
            basePrice = rentPrices[2] * duration;
        } else if (len == 2) {
            basePrice = rentPrices[3] * duration;
        } else if (len == 1) {
            basePrice = rentPrices[4] * duration;
        }

        return basePrice;
    }
}
