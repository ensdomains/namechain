// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {StringUtils} from "@ens/contracts/utils/StringUtils.sol";
import {IRentPriceOracle} from "./IRentPriceOracle.sol";
import {ITokenPriceOracle} from "./ITokenPriceOracle.sol";
import {HalvingUtils} from "../common/HalvingUtils.sol";

contract StandardRentPriceOracle is ERC165, IRentPriceOracle {
    uint8 public immutable priceDecimals;
    uint256[5] baseRatePerCp; // rate = price/sec
    uint64 public immutable premiumPeriod;
    uint64 public immutable premiumHalvingPeriod;
    uint256 public immutable premiumPriceInitial;
    uint256 public immutable premiumPriceOffset;
    ITokenPriceOracle public immutable tokenPriceOracle;
    mapping(IERC20Metadata => bool) _isPaymentToken;

    constructor(
        uint8 _priceDecimals,
        uint256[5] memory _baseRatePerCp,
        uint64 _premiumPeriod,
        uint64 _premiumHalvingPeriod,
        uint256 _premiumPriceInitial,
        ITokenPriceOracle _tokenPriceOracle,
        IERC20Metadata[] memory _paymentTokens
    ) {
        priceDecimals = _priceDecimals;
        baseRatePerCp = _baseRatePerCp;
        premiumPeriod = _premiumPeriod;
        premiumHalvingPeriod = _premiumHalvingPeriod;
        premiumPriceInitial = _premiumPriceInitial;
        premiumPriceOffset = HalvingUtils.halving(
            _premiumPriceInitial,
            _premiumHalvingPeriod,
            _premiumPeriod
        );
        tokenPriceOracle = _tokenPriceOracle;
        for (uint256 i; i < _paymentTokens.length; i++) {
            _isPaymentToken[_paymentTokens[i]] = true;
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
    function isPaymentToken(
        IERC20Metadata paymentToken
    ) external view returns (bool) {
        return _isPaymentToken[paymentToken];
    }

    /// @inheritdoc IRentPriceOracle
    /// @notice Does not check if normalized.
    function isValid(string memory label) external view returns (bool) {
        return baseRate(label) > 0;
    }

    /// @inheritdoc IRentPriceOracle
    function rentPrice(
        string memory label,
        uint64 expiry,
        uint64 duration,
        IERC20Metadata paymentToken
    ) public view returns (uint256 base, uint256 premium) {
        if (!_isPaymentToken[paymentToken]) {
            revert PaymentTokenNotSupported(paymentToken);
        }
        base = baseRate(label);
        if (base == 0) {
            revert NotRentable(label);
        }
        premium = premiumPrice(expiry);
        uint256 total = base * duration + premium; // revert on overflow
        uint256 amount = tokenPriceOracle.getTokenAmount(
            total,
            priceDecimals,
            paymentToken
        );
        premium = Math.mulDiv(amount, premium, total);
        base = amount - premium; // ensure: f(a+b) - f(a) == f(b)
    }

    /// @notice Get base rate to register or renew `label` for 1 second.
    /// @param label The name to price.
    /// @return The base rate or 0 if not rentable.
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
    /// @return The premium price.
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
