// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {StringUtils} from "@ens/contracts/utils/StringUtils.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IPermissionedRegistry} from "./../common/registry/interfaces/IPermissionedRegistry.sol";
import {LibHalving} from "./../common/utils/LibHalving.sol";
import {IRentPriceOracle} from "./interfaces/IRentPriceOracle.sol";

/// @param t Incremental time interval for discount, in seconds.
/// @param value Discount percentage, relative to `type(uint128).max`.
struct DiscountPoint {
    uint64 t;
    uint128 value;
}

/// @dev Structure to configure initial payment token and exchange rate.
struct PaymentRatio {
    IERC20 token;
    uint128 numer;
    uint128 denom;
}

contract StandardRentPriceOracle is ERC165, Ownable, IRentPriceOracle {
    ////////////////////////////////////////////////////////////////////////
    // Types
    ////////////////////////////////////////////////////////////////////////

    /// @dev Internal structure to store payment token exchange rate.
    struct Ratio {
        uint128 numer;
        uint128 denom;
    }

    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    IPermissionedRegistry public immutable REGISTRY;

    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    uint256[] internal _baseRatePerCp;

    DiscountPoint[] internal _discountPoints;

    mapping(IERC20 token => Ratio ratio) internal _paymentRatios;

    uint256 public premiumPriceInitial;

    uint64 public premiumHalvingPeriod;

    uint64 public premiumPeriod;

    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    /// @notice Discount points were changed.
    event DiscountPointsChanged(DiscountPoint[] points);

    /// @notice Base rates were changed.
    event BaseRatesChanged(uint256[] ratePerCp);

    /// @notice Premium pricing was changed.
    event PremiumPricingChanged(uint256 initialPrice, uint64 halvingPeriod, uint64 period);

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    /// @notice Invalid payment token exchange rate.
    /// @dev Error selector: `0x648564d3`
    error InvalidRatio();

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        address owner_,
        IPermissionedRegistry registry_,
        uint256[] memory baseRatePerCp_,
        DiscountPoint[] memory discountPoints_,
        uint256 premiumPriceInitial_,
        uint64 premiumHalvingPeriod_,
        uint64 premiumPeriod_,
        PaymentRatio[] memory paymentRatios_
    ) Ownable(owner_) {
        REGISTRY = registry_;

        _baseRatePerCp = baseRatePerCp_;
        emit BaseRatesChanged(baseRatePerCp_);

        _setDiscountPoints(discountPoints_);

        premiumPriceInitial = premiumPriceInitial_;
        premiumHalvingPeriod = premiumHalvingPeriod_;
        premiumPeriod = premiumPeriod_;
        emit PremiumPricingChanged(premiumPriceInitial_, premiumHalvingPeriod_, premiumPeriod_);

        for (uint256 i; i < paymentRatios_.length; ++i) {
            PaymentRatio memory x = paymentRatios_[i];
            if (x.numer == 0 || x.denom == 0) {
                revert InvalidRatio();
            }
            _paymentRatios[x.token] = Ratio(x.numer, x.denom);
            emit PaymentTokenAdded(x.token);
        }
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return
            interfaceId == type(IRentPriceOracle).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /// @notice Update base rates per codepoint.
    ///
    /// @dev - `ratePerCp[i]` corresponds to `i+1` codepoints.
    ///      - Larger lengths are priced by `ratePerCp[-1]`.
    ///      - Use rate of `0` to disable a specific length.
    ///      - Use empty array to disable all registrations.
    ///      - Emits `BaseRatesChanged`.
    ///
    /// @param ratePerCp The base rates, in base units per second.
    function updateBaseRates(uint256[] memory ratePerCp) external onlyOwner {
        _baseRatePerCp = ratePerCp;
        emit BaseRatesChanged(ratePerCp);
    }

    /// @notice Update the discount function.
    ///
    /// @dev - Each point is (∆t, intervalDiscount).
    ///      - Discounts are relative to `type(uint128).max`.
    ///        *  2yr @  5.00% ==  1yr @  0.00% +  1yr @ x =>  +1yr @ x = 10.00%
    ///        *  3yr @ 10.00% ==  2yr @  5.00% +  1yr @ x =>  +1yr @ x = 20.00%
    ///        *  5yr @ 17.50% ==  3yr @ 10.00% +  2yr @ x =>  +2yr @ x = 28.75%
    ///        * 10yr @ 25.00% ==  5yr @ 17.50% +  5yr @ x =>  +5yr @ x = 32.50%
    ///        * 25yr @ 30.00% == 10yr @ 25.00% + 15yr @ x => +15yr @ x = 33.33%
    ///      - Final discount is the derived from the weighted average over the intervals.
    ///      - Use empty array to disable.
    ///      - Emits `DiscountPointsChanged`.
    function updateDiscountPoints(DiscountPoint[] memory points) external onlyOwner {
        _setDiscountPoints(points);
    }

    /// @notice Update premium pricing function.
    ///
    /// @dev - Use `initialPrice = 0` to disable.
    ///      - Use `premiumPriceAfter(0)` to get exact starting price.
    ///      - `premiumPriceAfter(halvingPeriod) ~= premiumPriceAfter(0) / 2`.
    ///      - `premiumPriceAfter(halvingPeriod * x) ~= premiumPriceAfter(0) / 2^x`.
    ///      - `premiumPriceAfter(period) = 0`.
    ///      - Emits `PremiumPricingChanged`.
    ///
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
    ///
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

    /// @notice Get all base rates, in base units per second.
    function getBaseRates() external view returns (uint256[] memory) {
        return _baseRatePerCp;
    }

    /// @notice Get all discount function points.
    function getDiscountPoints() external view returns (DiscountPoint[] memory) {
        return _discountPoints;
    }

    /// @inheritdoc IRentPriceOracle
    ///
    /// @notice Does not check if normalized.
    function isValid(string memory label) external view returns (bool) {
        return baseRate(label) > 0;
    }

    /// @inheritdoc IRentPriceOracle
    function isPaymentToken(IERC20 paymentToken) public view returns (bool) {
        return _paymentRatios[paymentToken].denom > 0;
    }

    /// @notice Get base rate to register or renew `label` for 1 second.
    ///
    /// @param label The name to price.
    ///
    /// @return The base rate or 0 if not valid, in base units.
    function baseRate(string memory label) public view returns (uint256) {
        uint256 ncp = StringUtils.strlen(label);
        uint256 len = _baseRatePerCp.length;
        if (ncp == 0 || len == 0) return 0;
        return _baseRatePerCp[(ncp > len ? len : ncp) - 1];
    }

    /// @notice Compute integral of discount function for `duration`.
    ///
    /// @dev Use `integratedDiscount(t) / t` to compute average discount.
    ///
    /// @param duration The time since now, in seconds.
    ///
    /// @return Integral of discount function over `[0, duration)`.
    function integratedDiscount(uint64 duration) public view returns (uint256) {
        uint256 n = _discountPoints.length;
        if (n == 0) return 0;
        uint256 acc;
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            DiscountPoint memory p = _discountPoints[i];
            if (duration <= p.t) {
                return acc + duration * uint256(p.value);
            }
            duration -= p.t;
            acc += p.t * uint256(p.value);
            sum += p.t;
        }
        return acc + (duration * acc + sum - 1) / sum;
    }

    /// @notice Get premium price for an expiry relative to now.
    function premiumPrice(uint64 expiry) public view returns (uint256) {
        uint64 t = uint64(block.timestamp);
        return t >= expiry ? premiumPriceAfter(t - expiry) : 0;
    }

    /// @notice Get premium price for a duration after expiry.
    ///
    /// @dev Defined over `[0, premiumPeriod)`.
    ///
    /// @param duration The time after expiration, in seconds.
    ///
    /// @return The premium price, in base units.
    function premiumPriceAfter(uint64 duration) public view returns (uint256) {
        if (duration >= premiumPeriod) return 0;
        return
            LibHalving.halving(premiumPriceInitial, premiumHalvingPeriod, duration) -
            LibHalving.halving(premiumPriceInitial, premiumHalvingPeriod, premiumPeriod);
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
        (uint256 tokenId, uint64 oldExpiry, ) = REGISTRY.getNameData(label);
        uint64 t = oldExpiry > block.timestamp ? oldExpiry - uint64(block.timestamp) : 0;
        baseUnits -= Math.mulDiv(
            baseUnits,
            integratedDiscount(t + duration) - integratedDiscount(t),
            uint256(type(uint128).max) * duration
        );
        uint256 premiumUnits;
        if (owner != address(0)) {
            // prior owner pays no premium
            if (owner != REGISTRY.latestOwnerOf(tokenId)) {
                premiumUnits = premiumPrice(oldExpiry);
            }
        }
        // reverts on overflow
        premium = Math.mulDiv(premiumUnits, ratio.numer, ratio.denom);
        base =
            Math.mulDiv(baseUnits + premiumUnits, ratio.numer, ratio.denom, Math.Rounding.Ceil) -
            premium; // ensure: f(a+b) - f(a) == f(b)
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    /// @dev Replace the discount function points.
    function _setDiscountPoints(DiscountPoint[] memory points) internal {
        delete _discountPoints;
        for (uint256 i; i < points.length; ++i) {
            _discountPoints.push(points[i]);
        }
        emit DiscountPointsChanged(points);
    }
}
