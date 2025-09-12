// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {IRentPriceOracle} from "./IRentPriceOracle.sol";
import {HalvingUtils} from "../common/HalvingUtils.sol";
import {StringUtils} from "@ens/contracts/utils/StringUtils.sol";

struct PaymentRatio {
    IERC20 token;
    uint128 numer;
    uint128 denom;
}

uint256 constant DISCOUNT_SCALE = 1e18;

struct DiscountPoint {
    uint64 t;
    uint192 value; // relative to DISCOUNT_SCALE
}

contract StandardRentPriceOracle is ERC165, Ownable, IRentPriceOracle {
    struct Ratio {
        uint128 numer;
        uint128 denom;
    }

    /// @notice Discount function was changed.
    event DiscountFunctionChanged();

    /// @notice Invalid payment token exchange rate.
    /// @dev Error selector: `0x648564d3`
    error InvalidRatio();

    IPermissionedRegistry public immutable registry;
    uint256[5] baseRatePerCp; // rate = price/sec
    DiscountPoint[] discountPoints;
    uint64 public immutable premiumPeriod;
    uint64 public immutable premiumHalvingPeriod;
    uint256 public immutable premiumPriceInitial;
    uint256 public immutable premiumPriceOffset;
    mapping(IERC20 => Ratio) _paymentRatios;

    constructor(
        address owner,
        IPermissionedRegistry _registry,
        uint256[5] memory _baseRatePerCp,
        DiscountPoint[] memory _discountPoints,
        uint64 _premiumPeriod,
        uint64 _premiumHalvingPeriod,
        uint256 _premiumPriceInitial,
        PaymentRatio[] memory paymentRatios
    ) Ownable(owner) {
        registry = _registry;
        baseRatePerCp = _baseRatePerCp;
        _setDiscountPoints(_discountPoints);
        premiumPeriod = _premiumPeriod;
        premiumHalvingPeriod = _premiumHalvingPeriod;
        premiumPriceInitial = _premiumPriceInitial;
        premiumPriceOffset = HalvingUtils.halving(
            _premiumPriceInitial,
            _premiumHalvingPeriod,
            _premiumPeriod
        );
        for (uint256 i; i < paymentRatios.length; ++i) {
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

    /// @dev Update the discount function points.
    function _setDiscountPoints(DiscountPoint[] memory points) internal {
        delete discountPoints;
        for (uint256 i; i < points.length; ++i) {
            discountPoints.push(points[i]);
        }
    }

    /// @notice Update the discount function.
    /// @dev Use empty array to disable.
    function updateDiscountFunction(
        DiscountPoint[] memory points
    ) external onlyOwner {
        _setDiscountPoints(points);
        emit DiscountFunctionChanged();
    }

    /// @notice Update `paymentToken` support and/or exchange rate.
    /// @dev Use `denom = 0` to remove.
    /// - Emits `PaymentTokenAdded` if now supported.
    /// - Emits `PaymentTokenRemoved` if no longer supported.
    /// - Reverts if invalid exchange rate.
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
        if (ncp == 0) return 0;
        return
            baseRatePerCp[
                (ncp > baseRatePerCp.length ? baseRatePerCp.length : ncp) - 1
            ];
    }

    /// @notice Compute integral of discount function for `duration`.
    /// @dev Use `integratedDiscount(t) / t` to compute average discount.
    /// @param duration The time since now, in seconds.
    /// @return Integral of discount function over `[0, duration)`.
    function integratedDiscount(uint64 duration) public view returns (uint256) {
        uint256 n = discountPoints.length;
        if (n == 0) return 0;
        uint256 t;
        uint256 acc;
        uint256 value;
        DiscountPoint memory p;
        for (uint256 i; i < n; ++i) {
            p = discountPoints[i];
            uint256 dt = p.t - t;
            value = (p.t * p.value - acc + (dt - 1)) / dt; // round up
            if (duration < p.t) break;
            t = p.t;
            acc += dt * value;
        }
        return acc + (duration - t) * (duration > p.t ? p.value : value);
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
            ) - premiumPriceOffset;
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
        (uint256 tokenId, uint64 oldExpiry, ) = registry.getNameData(label);
        uint64 t = oldExpiry > block.timestamp
            ? oldExpiry - uint64(block.timestamp)
            : 0;
        baseUnits -= Math.mulDiv(
            baseUnits,
            integratedDiscount(t + duration) - integratedDiscount(t),
            DISCOUNT_SCALE * duration
        );
        uint256 premiumUnits;
        if (owner != address(0)) {
            // prior owner pays no premium
            if (owner != registry.latestOwnerOf(tokenId)) {
                premiumUnits = premiumPrice(oldExpiry);
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
