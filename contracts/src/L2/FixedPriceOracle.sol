//SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {IPriceOracle} from "@ens/contracts/ethregistrar/IPriceOracle.sol";
import {StringUtils} from "@ens/contracts/utils/StringUtils.sol";

// same as StablePriceOracle but has no underlying oracle
contract FixedPriceOracle is ERC165, IPriceOracle {
    uint256 public immutable price1Letter;
    uint256 public immutable price2Letter;
    uint256 public immutable price3Letter;
    uint256 public immutable price4Letter;
    uint256 public immutable price5Letter;

    constructor(uint256[5] memory _rentPrices) {
        price1Letter = _rentPrices[0];
        price2Letter = _rentPrices[1];
        price3Letter = _rentPrices[2];
        price4Letter = _rentPrices[3];
        price5Letter = _rentPrices[4];
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IPriceOracle).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IPriceOracle
    function price(
        string calldata name,
        uint256 /*expires*/,
        uint256 duration
    ) external view override returns (IPriceOracle.Price memory) {
        uint256 len = StringUtils.strlen(name);
        uint256 basePrice;

        if (len >= 5) {
            basePrice = price5Letter * duration;
        } else if (len == 4) {
            basePrice = price4Letter * duration;
        } else if (len == 3) {
            basePrice = price3Letter * duration;
        } else if (len == 2) {
            basePrice = price2Letter * duration;
        } else {
            basePrice = price1Letter * duration;
        }

        return IPriceOracle.Price({base: basePrice, premium: 0});
    }
}
