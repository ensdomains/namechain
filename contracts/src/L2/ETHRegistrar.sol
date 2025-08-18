// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IETHRegistrar, PRICE_DECIMALS} from "./IETHRegistrar.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {EnhancedAccessControl, LibEACBaseRoles} from "../common/EnhancedAccessControl.sol";
import {LibRegistryRoles} from "../common/LibRegistryRoles.sol";
import {StringUtils} from "@ens/contracts/utils/StringUtils.sol";
import {PriceUtils} from "../common/PriceUtils.sol";

uint256 constant REGISTRATION_ROLE_BITMAP = LibRegistryRoles
    .ROLE_SET_SUBREGISTRY |
    LibRegistryRoles.ROLE_SET_SUBREGISTRY_ADMIN |
    LibRegistryRoles.ROLE_SET_RESOLVER |
    LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN;

contract ETHRegistrar is IETHRegistrar, EnhancedAccessControl {
    struct ConstructorArgs {
        IPermissionedRegistry ethRegistry;
        address beneficiary;
        uint64 minCommitmentAge;
        uint64 maxCommitmentAge;
        uint64 minRegistrationDuration;
        uint64 gracePeriod;
        uint256[5] baseRatePerCp;
        uint64 premiumPeriod;
        uint64 premiumHalvingPeriod;
        uint256 premiumPriceInitial;
        IERC20Metadata[] paymentTokens;
    }

    uint8 public constant priceDecimals = PRICE_DECIMALS; // fixed, otherwise needs included in events

    IPermissionedRegistry public immutable ethRegistry; // [register, expiry)
    address public immutable beneficiary;
    uint64 public immutable minCommitmentAge; // [min, max)
    uint64 public immutable maxCommitmentAge;
    uint64 public immutable minRegistrationDuration; // [min, inf)
    uint64 public immutable gracePeriod;
    uint256[5] baseRatePerCp; // rate = price/sec
    uint64 public immutable premiumPeriod;
    uint64 public immutable premiumHalvingPeriod;
    uint256 public immutable premiumPriceInitial;
    uint256 public immutable premiumPriceOffset;

    mapping(IERC20Metadata => bool) _isPaymentToken;
    mapping(bytes32 => uint64) public _commitTime;

    constructor(ConstructorArgs memory args) {
        if (args.maxCommitmentAge <= args.minCommitmentAge) {
            revert MaxCommitmentAgeTooLow();
        }
        _grantRoles(
            ROOT_RESOURCE,
            LibEACBaseRoles.ALL_ROLES,
            _msgSender(),
            true
        );
        ethRegistry = args.ethRegistry;
        beneficiary = args.beneficiary;
        minCommitmentAge = args.minCommitmentAge;
        maxCommitmentAge = args.maxCommitmentAge;
        minRegistrationDuration = args.minRegistrationDuration;
        gracePeriod = args.gracePeriod;
        baseRatePerCp = args.baseRatePerCp;
        premiumPeriod = args.premiumPeriod;
        premiumHalvingPeriod = args.premiumHalvingPeriod;
        premiumPriceInitial = args.premiumPriceInitial;
        premiumPriceOffset = PriceUtils.halving(
            args.premiumPriceInitial,
            args.premiumHalvingPeriod,
            args.premiumPeriod
        );
        for (uint256 i; i < args.paymentTokens.length; i++) {
            _setPaymentToken(args.paymentTokens[i], true);
        }
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(EnhancedAccessControl) returns (bool) {
        return
            interfaceId == type(IETHRegistrar).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // function setPaymentToken(IERC20Metadata paymentToken, bool supported) external onlyRootRoles(LibRegistryRoles.ROLE_CONFIGURE_ADMIN) {
    // 	_setPaymentToken(token, supported);
    // }

    /// @dev Internal logic for enabling a payment token.
    function _setPaymentToken(
        IERC20Metadata paymentToken,
        bool supported
    ) internal {
        _isPaymentToken[paymentToken] = supported;
        emit PaymentTokenChanged(paymentToken, supported);
    }

    modifier onlyPaymentToken(IERC20Metadata paymentToken) {
        if (!_isPaymentToken[paymentToken]) {
            revert PaymentTokenNotSupported(paymentToken);
        }
        _;
    }

    /// @inheritdoc IETHRegistrar
    function isPaymentToken(
        IERC20Metadata paymentToken
    ) external view returns (bool) {
        return _isPaymentToken[paymentToken];
    }

    /// @inheritdoc IETHRegistrar
    function isValid(string memory label) external pure returns (bool) {
        return _isValidLength(StringUtils.strlen(label));
    }

    /// @dev Internal logic for valid label length.
    function _isValidLength(uint256 ncp) internal pure returns (bool) {
        return ncp >= 3;
    }

    /// @inheritdoc IETHRegistrar
    function isAvailable(string memory label) external view returns (bool) {
        (, uint64 expiry, ) = ethRegistry.getNameData(label);
        return _isAvailable(expiry);
    }

    /// @dev Internal logic for registration availability.
    function _isAvailable(uint256 expiry) internal view returns (bool) {
        return block.timestamp >= expiry + gracePeriod;
    }

    /// @dev Get base price to register or renew `label` with `duration`.
    /// @notice Use `duration = 1` for rate (price/sec).
    /// @param label The name to price.
    /// @param duration The duration to price, in seconds.
    /// @return The base price.
    function basePrice(
        string memory label,
        uint64 duration
    ) public view returns (uint256) {
        uint256 ncp = StringUtils.strlen(label);
        if (!_isValidLength(ncp)) {
            revert NoRentPrice(label);
        }
        uint256 baseRate = baseRatePerCp[
            (ncp > baseRatePerCp.length ? baseRatePerCp.length : ncp) - 1
        ];
        return baseRate * duration;
    }

    /// @dev Get premium price for a duration after expiry.
    /// @param duration The time after expiration, in seconds.
    /// @return The premium price.
    function premiumPriceAfter(uint64 duration) public view returns (uint256) {
        if (duration >= premiumPeriod) return 0;
        return
            PriceUtils.halving(
                premiumPriceInitial,
                premiumHalvingPeriod,
                duration
            ) - premiumPriceOffset;
    }

    /// @dev Get premium price for a name.
    /// @param label The name to price.
    /// @return The premium price.
    function premiumPrice(string memory label) public view returns (uint256) {
        (, uint64 expiry, ) = ethRegistry.getNameData(label);
        return _premiumPriceFromExpiry(expiry);
    }

    /// @dev Get premium price for an expiry relative to now.
    function _premiumPriceFromExpiry(
        uint64 expiry
    ) internal view returns (uint256) {
        uint64 t0 = expiry + gracePeriod;
        uint64 t = uint64(block.timestamp);
        return t >= t0 ? premiumPriceAfter(t - t0) : 0;
    }

    /// @inheritdoc IETHRegistrar
    function rentPrice(
        string memory label,
        uint64 duration
    ) public view returns (uint256 base, uint256 premium) {
        base = basePrice(label, duration);
        premium = premiumPrice(label);
    }

    /// @inheritdoc IETHRegistrar
    function rentPrice(
        string memory label,
        uint64 duration,
        IERC20Metadata paymentToken
    )
        external
        view
        onlyPaymentToken(paymentToken)
        returns (uint256 base, uint256 premium)
    {
        (base, premium) = rentPrice(label, duration);
        uint256 total = base + premium;
        uint8 decimals = paymentToken.decimals();
        base = PriceUtils.convertDecimals(base, priceDecimals, decimals);
        premium =
            PriceUtils.convertDecimals(total, priceDecimals, decimals) -
            base;
    }

    /// @inheritdoc IETHRegistrar
    function makeCommitment(
        string memory name,
        address owner,
        bytes32 secret,
        IRegistry subregistry,
        address resolver,
        uint64 duration
    ) public pure override returns (bytes32) {
        return
            keccak256(
                abi.encode(name, owner, secret, subregistry, resolver, duration)
            );
    }

    /// @inheritdoc IETHRegistrar
    function commitmentAt(bytes32 commitment) external view returns (uint64) {
        return _commitTime[commitment];
    }

    /// @inheritdoc IETHRegistrar
    function commit(bytes32 commitment) external {
        if (_commitTime[commitment] + maxCommitmentAge > block.timestamp) {
            revert UnexpiredCommitmentExists(commitment);
        }
        _commitTime[commitment] = uint64(block.timestamp);
        emit CommitmentMade(commitment);
    }

    /// @dev Assert `commitment` is timely, then delete it.
    function _consumeCommitment(bytes32 commitment) internal {
        uint64 t = uint64(block.timestamp);
        uint64 t0 = _commitTime[commitment];
        uint64 tMin = t0 + minCommitmentAge;
        if (t < tMin) {
            revert CommitmentTooNew(commitment, tMin, t);
        }
        uint64 tMax = t0 + maxCommitmentAge;
        if (t >= tMax) {
            revert CommitmentTooOld(commitment, tMax, t);
        }
        delete _commitTime[commitment];
    }

    /// @inheritdoc IETHRegistrar
    function register(
        string memory label,
        address owner,
        bytes32 secret,
        IRegistry subregistry,
        address resolver,
        uint64 duration,
        IERC20Metadata paymentToken,
        bytes32 referer
    ) external onlyPaymentToken(paymentToken) returns (uint256 tokenId) {
        (, uint64 expiry, ) = ethRegistry.getNameData(label);
        if (!_isAvailable(expiry)) {
            revert NameAlreadyRegistered(label);
        }
        if (duration < minRegistrationDuration) {
            revert DurationTooShort(duration, minRegistrationDuration);
        }
        _consumeCommitment(
            makeCommitment(
                label,
                owner,
                secret,
                subregistry,
                resolver,
                duration
            )
        );
        uint256 base = basePrice(label, duration);
        uint256 premium = _premiumPriceFromExpiry(expiry);
        uint256 tokenAmount = PriceUtils.convertDecimals(
            base + premium,
            priceDecimals,
            paymentToken.decimals()
        );
        SafeERC20.safeTransferFrom(
            paymentToken,
            _msgSender(),
            beneficiary,
            tokenAmount
        );
        tokenId = ethRegistry.register(
            label,
            owner,
            subregistry,
            resolver,
            REGISTRATION_ROLE_BITMAP,
            uint64(block.timestamp) + duration
        );
        emit NameRegistered(
            tokenId,
            label,
            owner,
            subregistry,
            resolver,
            duration,
            paymentToken,
            referer,
            base,
            premium
        );
    }

    /// @inheritdoc IETHRegistrar
    function renew(
        string memory label,
        uint64 duration,
        IERC20Metadata paymentToken,
        bytes32 referer
    ) external onlyPaymentToken(paymentToken) {
        (uint256 tokenId, uint64 oldExpiry, ) = ethRegistry.getNameData(label);
        if (_isAvailable(oldExpiry)) {
            revert NameNotRegistered(label);
        }
        // Check for overflow before any state changes
        if (oldExpiry > type(uint64).max - duration) {
            revert DurationOverflow(oldExpiry, duration);
        }
        uint64 expires = oldExpiry + duration;
        uint256 base = basePrice(label, duration);
        uint256 tokenAmount = PriceUtils.convertDecimals(
            base,
            priceDecimals,
            paymentToken.decimals()
        );
        SafeERC20.safeTransferFrom(
            paymentToken,
            _msgSender(),
            beneficiary,
            tokenAmount
        );
        ethRegistry.renew(tokenId, expires);
        emit NameRenewed(
            tokenId,
            label,
            duration,
            expires,
            paymentToken,
            referer,
            base
        );
    }
}
