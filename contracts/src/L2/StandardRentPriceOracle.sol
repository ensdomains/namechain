// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

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

contract StandardRentPriceOracle is ERC165, IRentPriceOracle {
    struct Ratio {
        uint128 numer;
        uint128 denom;
    }

    IPermissionedRegistry public immutable registry;
    uint256[5] baseRatePerCp; // rate = price/sec
    uint64 public immutable premiumPeriod;
    uint64 public immutable premiumHalvingPeriod;
    uint256 public immutable premiumPriceInitial;
    uint256 public immutable premiumPriceOffset;
    mapping(IERC20 => Ratio) _paymentRatios;

    constructor(
        IPermissionedRegistry _registry,
        uint256[5] memory _baseRatePerCp,
        uint64 _premiumPeriod,
        uint64 _premiumHalvingPeriod,
        uint256 _premiumPriceInitial,
        PaymentRatio[] memory paymentRatios
    ) {
        registry = _registry;
        baseRatePerCp = _baseRatePerCp;
        premiumPeriod = _premiumPeriod;
        premiumHalvingPeriod = _premiumHalvingPeriod;
        premiumPriceInitial = _premiumPriceInitial;
        premiumPriceOffset = HalvingUtils.halving(
            _premiumPriceInitial,
            _premiumHalvingPeriod,
            _premiumPeriod
        );
        for (uint256 i; i < paymentRatios.length; i++) {
            PaymentRatio memory x = paymentRatios[i];
            _paymentRatios[x.token] = Ratio(x.numer, x.denom);
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

    /// @inheritdoc IRentPriceOracle
    function isPaymentToken(IERC20 paymentToken) external view returns (bool) {
        return _paymentRatios[paymentToken].denom > 0;
    }

    /// @inheritdoc IRentPriceOracle
    /// @notice Does not check if normalized.
    function isValid(string memory label) external view returns (bool) {
        return baseRate(label) > 0;
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
            (uint256 tokenId, uint64 expiry, ) = registry.getNameData(label);
            if (owner != registry.latestOwnerOf(tokenId)) {
                premiumUnits = premiumPrice(expiry);
            }
        }
        // reverts on overflow
        base = Math.mulDiv(baseUnits, ratio.numer, ratio.denom);
        premium = Math.mulDiv(premiumUnits, ratio.numer, ratio.denom);
    }

    /// @notice Get base rate to register or renew `label` for 1 second.
    /// @param label The name to price.
    /// @return The base rate or 0 if not rentable, in base units.
    function baseRate(string memory label) public view returns (uint256) {
        uint256 ncp = StringUtils.strlen(label);
        if (ncp == 0) return 0;
        return
            baseRatePerCp[
                (ncp > baseRatePerCp.length ? baseRatePerCp.length : ncp) - 1
            ];
    }

    /// @notice Get premium price for an expiry relative to now.
    function premiumPrice(uint64 expiry) public view returns (uint256) {
        uint64 t = uint64(block.timestamp);
        return t >= expiry ? premiumPriceAfter(t - expiry) : 0;
    }

    /// @notice Get premium price for a duration after expiry.
    ///         Positive over `[0, premiumPeriod)`.
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
}
