// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IPriceOracle} from "../registry/IPriceOracle.sol";

contract MockPriceOracle is IPriceOracle {
    uint256 public basePrice;
    uint256 public premiumPrice;

    constructor(uint256 _basePrice, uint256 _premiumPrice) {
        basePrice = _basePrice;
        premiumPrice = _premiumPrice;
    }

    function price(
        string calldata /*name*/,
        uint256 /*expires*/,
        uint256 /*duration*/
    ) external view returns (Price memory) {
        return Price(basePrice, premiumPrice);
    }
}
