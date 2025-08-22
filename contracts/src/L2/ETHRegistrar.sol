// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IETHRegistrar} from "./IETHRegistrar.sol";
import {IRentPriceOracle} from "./IRentPriceOracle.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {EnhancedAccessControl, LibEACBaseRoles} from "../common/EnhancedAccessControl.sol";
import {LibRegistryRoles} from "../common/LibRegistryRoles.sol";

uint256 constant REGISTRATION_ROLE_BITMAP = LibRegistryRoles
    .ROLE_SET_SUBREGISTRY |
    LibRegistryRoles.ROLE_SET_SUBREGISTRY_ADMIN |
    LibRegistryRoles.ROLE_SET_RESOLVER |
    LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN;

uint256 constant ROLE_SET_ORACLE = 1 << 0;

contract ETHRegistrar is IETHRegistrar, EnhancedAccessControl {
    IPermissionedRegistry public immutable registry; // [register, expiry)
    address public immutable beneficiary;
    uint64 public immutable minCommitmentAge; // [min, max)
    uint64 public immutable maxCommitmentAge;
    uint64 public immutable minRegisterDuration; // [min, inf)
    uint64 public immutable minRenewDuration; // [min, inf)
    IRentPriceOracle public rentPriceOracle;

    mapping(bytes32 => uint64) _commitTime;

    event RentPriceOracleChanged();

    constructor(
        IPermissionedRegistry _registry,
        address _beneficiary,
        uint64 _minCommitmentAge,
        uint64 _maxCommitmentAge,
        uint64 _minRegisterDuration,
        IRentPriceOracle _rentPriceOracle
    ) {
        if (_maxCommitmentAge <= _minCommitmentAge) {
            revert MaxCommitmentAgeTooLow();
        }
        _grantRoles(
            ROOT_RESOURCE,
            LibEACBaseRoles.ALL_ROLES,
            _msgSender(),
            true
        );
        registry = _registry;
        beneficiary = _beneficiary;
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
        minRegisterDuration = _minRegisterDuration;
        rentPriceOracle = _rentPriceOracle;
    }

    /// @inheritdoc EnhancedAccessControl
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(EnhancedAccessControl) returns (bool) {
        return
            interfaceId == type(IETHRegistrar).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @dev Change the rent price oracle.
    function setRentPriceOracle(
        IRentPriceOracle oracle
    ) external onlyRootRoles(ROLE_SET_ORACLE) {
        rentPriceOracle = oracle;
        emit RentPriceOracleChanged();
    }

    /// @inheritdoc IETHRegistrar
    function isPaymentToken(
        IERC20Metadata paymentToken
    ) external view returns (bool) {
        return rentPriceOracle.isPaymentToken(paymentToken);
    }

    /// @inheritdoc IETHRegistrar
    function isValid(string memory label) external view returns (bool) {
        return rentPriceOracle.isValid(label);
    }

    /// @inheritdoc IETHRegistrar
    function rentPrice(
        string memory label,
        address owner,
        uint64 duration,
        IERC20Metadata paymentToken
    ) public view returns (uint256 base, uint256 premium) {
        (uint256 tokenId, uint64 expiry, ) = registry.getNameData(label);
        (base, premium) = rentPriceOracle.rentPrice(
            label,
            expiry,
            duration,
            paymentToken
        );
        if (owner != address(0) && owner == registry.latestOwnerOf(tokenId)) {
            premium = 0;
        }
    }

    /// @inheritdoc IETHRegistrar
    function isAvailable(string memory label) external view returns (bool) {
        (, uint64 expiry, ) = registry.getNameData(label);
        return _isAvailable(expiry);
    }

    /// @dev Internal logic for registration availability.
    function _isAvailable(uint256 expiry) internal view returns (bool) {
        return block.timestamp >= expiry;
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
    ) external returns (uint256 tokenId) {
        (, uint64 oldExpiry, ) = registry.getNameData(label);
        if (!_isAvailable(oldExpiry)) {
            revert NameAlreadyRegistered(label);
        }
        if (duration < minRegisterDuration) {
            revert DurationTooShort(duration, minRegisterDuration);
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
        (uint256 base, uint256 premium) = rentPrice(
            label,
            owner,
            duration,
            paymentToken
        ); // reverts if !isValid or !isPaymentToken
        paymentToken.transferFrom(_msgSender(), beneficiary, base + premium); // reverts if payment failed
        tokenId = registry.register(
            label,
            owner,
            subregistry,
            resolver,
            REGISTRATION_ROLE_BITMAP,
            _addDuration(uint64(block.timestamp), duration)
        ); // reverts if owner is null
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
    ) external {
        (uint256 tokenId, uint64 oldExpiry, ) = registry.getNameData(label);
        if (_isAvailable(oldExpiry)) {
            revert NameNotRegistered(label);
        }
        if (duration == 0) {
            revert DurationTooShort(duration, 1); /// ???
        }
        uint64 expires = _addDuration(oldExpiry, duration);
        (uint256 base, ) = rentPrice(
            label,
            registry.ownerOf(tokenId),
            duration,
            paymentToken
        ); // reverts if !isValid or !isPaymentToken
        paymentToken.transferFrom(_msgSender(), beneficiary, base); // reverts if payment failed
        registry.renew(tokenId, expires);
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

    /// @dev Ensure `expiry + duration` does not overflow.
    function _addDuration(
        uint64 expiry,
        uint64 duration
    ) internal pure returns (uint64 sum) {
        unchecked {
            sum = expiry + duration;
        }
        if (sum < expiry) {
            revert DurationOverflow(expiry, duration);
        }
    }
}
