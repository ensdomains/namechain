// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {IRegistryDatastore} from "../common/IRegistryDatastore.sol";
import {IRentPriceOracle} from "./IRentPriceOracle.sol";
import {HalvingUtils} from "../common/HalvingUtils.sol";
import {StringUtils} from "@ens/contracts/utils/StringUtils.sol";

struct PaymentRatio {
    IERC20 token;
    uint128 numer;
    uint128 denom;
}

contract StandardRentPriceOracle is ERC165, Ownable, IRentPriceOracle {
    struct Ratio {
        uint128 numer;
        uint128 denom;
    }

    /// @notice Invalid payment token exchange rate.
    /// @dev Error selector: `0x648564d3`
    error InvalidRatio();

    /// @notice Base rates were changed.
    event BaseRatesChanged(uint256[] ratePerCp);

    /// @notice Premium pricing was changed.
    event PremiumPricingChanged(
        uint256 initialPrice,
        uint64 halvingPeriod,
        uint64 period
    );

    IPermissionedRegistry public immutable registry;
    uint256[] baseRatePerCp;
    uint256 public premiumPriceInitial;
    uint64 public premiumHalvingPeriod;
    uint64 public premiumPeriod;
    mapping(IERC20 => Ratio) _paymentRatios;

    constructor(
        address owner,
        IPermissionedRegistry _registry,
        uint256[] memory _baseRatePerCp,
        uint256 _premiumPriceInitial,
        uint64 _premiumHalvingPeriod,
        uint64 _premiumPeriod,
        PaymentRatio[] memory paymentRatios
    ) Ownable(owner) {
        registry = _registry;

        baseRatePerCp = _baseRatePerCp;
        emit BaseRatesChanged(_baseRatePerCp);

        premiumPriceInitial = _premiumPriceInitial;
        premiumHalvingPeriod = _premiumHalvingPeriod;
        premiumPeriod = _premiumPeriod;
        emit PremiumPricingChanged(
            _premiumPriceInitial,
            _premiumHalvingPeriod,
            _premiumPeriod
        );

        for (uint256 i; i < paymentRatios.length; i++) {
            PaymentRatio memory x = paymentRatios[i];
            if (x.numer == 0 || x.denom == 0) {
                revert InvalidRatio();
            }
            _paymentRatios[x.token] = Ratio(x.numer, x.denom);
            emit PaymentTokenAdded(x.token);
        }
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IRentPriceOracle).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @notice Update base rates (price/sec) per codepoint.
    /// @dev - `ratePerCp[i]` corresponds to `i+1` codepoints.
    ///      - Larger lengths are priced by `ratePerCp[-1]`.
    ///      - Use rate of `0` to disable a specific length.
    ///      - Use empty array to disable all registrations.
    ///      - Emits `BaseRatesChanged`.
    /// @param ratePerCp The base rates, in base units.
    function updateBaseRates(uint256[] memory ratePerCp) external onlyOwner {
        baseRatePerCp = ratePerCp;
        emit BaseRatesChanged(ratePerCp);
    }

    /// @notice Update premium pricing function.
    /// @dev - Use `initialPrice = 0` to disable.
    ///      - Use `premiumPriceAfter(0)` to get exact starting price.
    ///      - `premiumPriceAfter(halvingPeriod) ~= premiumPriceAfter(0) / 2`.
    ///      - `premiumPriceAfter(halvingPeriod * x) ~= premiumPriceAfter(0) / 2^x`.
    ///      - `premiumPriceAfter(period) = 0`.
    ///      - Emits `PremiumPricingChanged`.
    /// @param initialPrice The initial price, in base units.
    /// @param halvingPeriod Duration until the price is reduced in half.
    /// @param period Number of seconds until the price is reduced to 0.
    function updatePremiumPricing(
        uint256 initialPrice,
        uint64 halvingPeriod,
        uint64 period
    ) external onlyOwner {
        premiumPriceInitial = initialPrice;
        premiumHalvingPeriod = halvingPeriod;
        premiumPeriod = period;
        emit PremiumPricingChanged(initialPrice, halvingPeriod, period);
    }

    /// @notice Update `paymentToken` support and/or exchange rate.
    /// @dev - Use `denom = 0` to remove.
    ///      - Emits `PaymentTokenAdded` if now supported.
    ///      - Emits `PaymentTokenRemoved` if no longer supported.
    ///      - Reverts if invalid exchange rate.
    function updatePaymentToken(
        IERC20 paymentToken,
        uint128 numer,
        uint128 denom
    ) external onlyOwner {
        bool active = isPaymentToken(paymentToken);
        if (denom > 0) {
            if (numer == 0) {
                revert InvalidRatio();
            }
            _paymentRatios[paymentToken] = Ratio(numer, denom);
            if (!active) {
                emit PaymentTokenAdded(paymentToken);
            }
        } else if (active) {
            delete _paymentRatios[paymentToken];
            emit PaymentTokenRemoved(paymentToken);
        }
    }

    /// @inheritdoc IRentPriceOracle
    function isPaymentToken(IERC20 paymentToken) public view returns (bool) {
        return _paymentRatios[paymentToken].denom > 0;
    }

    /// @inheritdoc IRentPriceOracle
    /// @notice Does not check if normalized.
    function isValid(string memory label) external view returns (bool) {
        return baseRate(label) > 0;
    }

    /// @notice Get base rate to register or renew `label` for 1 second.
    /// @param label The name to price.
    /// @return The base rate or 0 if not valid, in base units.
    function baseRate(string memory label) public view returns (uint256) {
        uint256 ncp = StringUtils.strlen(label);
        if (ncp == 0 || baseRatePerCp.length == 0) return 0;
        if (ncp > baseRatePerCp.length) {
            ncp = baseRatePerCp.length;
        }
        return baseRatePerCp[ncp - 1];
    }

    /// @notice Get premium price for an expiry relative to now.
    function premiumPrice(uint64 expiry) public view returns (uint256) {
        uint64 t = uint64(block.timestamp);
        return t >= expiry ? premiumPriceAfter(t - expiry) : 0;
    }

    /// @notice Get premium price for a duration after expiry.
    /// @dev Defined over `[0, premiumPeriod)`.
    /// @param duration The time after expiration, in seconds.
    /// @return The premium price, in base units.
    function premiumPriceAfter(uint64 duration) public view returns (uint256) {
        if (duration >= premiumPeriod) return 0;
        return
            HalvingUtils.halving(
                premiumPriceInitial,
                premiumHalvingPeriod,
                duration
            ) -
            HalvingUtils.halving(
                premiumPriceInitial,
                premiumHalvingPeriod,
                premiumPeriod
            );
    }

    /// @inheritdoc IRentPriceOracle
    function rentPrice(
        string memory label,
        address owner,
        uint64 duration,
        IERC20 paymentToken
    ) public view returns (uint256 base, uint256 premium) {
        Ratio memory ratio = _paymentRatios[paymentToken];
        if (ratio.denom == 0) {
            revert PaymentTokenNotSupported(paymentToken);
        }
        uint256 baseUnits = baseRate(label) * duration;
        if (baseUnits == 0) {
            revert NotValid(label);
        }
        uint256 premiumUnits;
        if (owner != address(0)) {
            // prior owner pays no premium
            (uint256 tokenId, IRegistryDatastore.Entry memory entry) = registry.getNameData(label);
            uint64 expiry = entry.expiry;
            if (owner != registry.latestOwnerOf(tokenId)) {
                premiumUnits = premiumPrice(expiry);
            }
        }
        // reverts on overflow
        premium = Math.mulDiv(premiumUnits, ratio.numer, ratio.denom);
        base =
            Math.mulDiv(
                baseUnits + premiumUnits,
                ratio.numer,
                ratio.denom,
                Math.Rounding.Ceil
            ) -
            premium; // ensure: f(a+b) - f(a) == f(b)
    }
}
