// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {EnhancedAccessControl} from "../../common/access-control/EnhancedAccessControl.sol";
import {EACBaseRolesLib} from "../../common/access-control/libraries/EACBaseRolesLib.sol";
import {IPermissionedRegistry} from "../../common/registry/interfaces/IPermissionedRegistry.sol";
import {IRegistry} from "../../common/registry/interfaces/IRegistry.sol";
import {IRegistryDatastore} from "../../common/registry/interfaces/IRegistryDatastore.sol";
import {RegistryRolesLib} from "../../common/registry/libraries/RegistryRolesLib.sol";

import {IETHRegistrar} from "./interfaces/IETHRegistrar.sol";
import {IRentPriceOracle} from "./interfaces/IRentPriceOracle.sol";

uint256 constant REGISTRATION_ROLE_BITMAP = RegistryRolesLib.ROLE_SET_SUBREGISTRY |
    RegistryRolesLib.ROLE_SET_SUBREGISTRY_ADMIN |
    RegistryRolesLib.ROLE_SET_RESOLVER |
    RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN |
    RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;

uint256 constant ROLE_SET_ORACLE = 1 << 0;

contract ETHRegistrar is IETHRegistrar, EnhancedAccessControl {
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    IPermissionedRegistry public immutable REGISTRY;

    address public immutable BENEFICIARY;

    uint64 public immutable MIN_COMMITMENT_AGE;

    uint64 public immutable MAX_COMMITMENT_AGE;

    uint64 public immutable MIN_REGISTER_DURATION;

    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    IRentPriceOracle public rentPriceOracle;

    mapping(bytes32 commitment => uint64 commitTime) private _commitTime;

    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    event RentPriceOracleChanged(IRentPriceOracle oracle);

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        IPermissionedRegistry registry_,
        address beneficiary_,
        uint64 minCommitmentAge_,
        uint64 maxCommitmentAge_,
        uint64 minRegisterDuration_,
        IRentPriceOracle rentPriceOracle_
    ) {
        if (maxCommitmentAge_ <= minCommitmentAge_) {
            revert MaxCommitmentAgeTooLow();
        }
        _grantRoles(ROOT_RESOURCE, EACBaseRolesLib.ALL_ROLES, _msgSender(), true);

        REGISTRY = registry_;
        BENEFICIARY = beneficiary_;
        MIN_COMMITMENT_AGE = minCommitmentAge_;
        MAX_COMMITMENT_AGE = maxCommitmentAge_;
        MIN_REGISTER_DURATION = minRegisterDuration_;

        rentPriceOracle = rentPriceOracle_;
        emit RentPriceOracleChanged(rentPriceOracle_);
    }

    /// @inheritdoc EnhancedAccessControl
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(EnhancedAccessControl) returns (bool) {
        return
            interfaceId == type(IETHRegistrar).interfaceId ||
            interfaceId == type(IRentPriceOracle).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /// @dev Change the rent price oracle.
    function setRentPriceOracle(IRentPriceOracle oracle) external onlyRootRoles(ROLE_SET_ORACLE) {
        rentPriceOracle = oracle;
        emit RentPriceOracleChanged(oracle);
    }

    /// @inheritdoc IETHRegistrar
    function commit(bytes32 commitment) external {
        if (_commitTime[commitment] + MAX_COMMITMENT_AGE > block.timestamp) {
            revert UnexpiredCommitmentExists(commitment);
        }
        _commitTime[commitment] = uint64(block.timestamp);
        emit CommitmentMade(commitment);
    }

    /// @inheritdoc IETHRegistrar
    function register(
        string memory label,
        address owner,
        bytes32 secret,
        IRegistry subregistry,
        address resolver,
        uint64 duration,
        IERC20 paymentToken,
        bytes32 referrer
    ) external returns (uint256 tokenId) {
        (, IRegistryDatastore.Entry memory entry) = REGISTRY.getNameData(label);
        uint64 oldExpiry = entry.expiry;
        if (!_isAvailable(oldExpiry)) {
            revert NameAlreadyRegistered(label);
        }
        if (duration < MIN_REGISTER_DURATION) {
            revert DurationTooShort(duration, MIN_REGISTER_DURATION);
        }
        _consumeCommitment(
            makeCommitment(label, owner, secret, subregistry, resolver, duration, referrer)
        );
        (uint256 base, uint256 premium) = rentPrice(label, owner, duration, paymentToken); // reverts if !isValid or !isPaymentToken
        // TODO: custom error
        require(paymentToken.transferFrom(_msgSender(), BENEFICIARY, base + premium)); // reverts if payment failed
        tokenId = REGISTRY.register(
            label,
            owner,
            subregistry,
            resolver,
            REGISTRATION_ROLE_BITMAP,
            uint64(block.timestamp) + duration
        ); // reverts if owner is null
        emit NameRegistered(
            tokenId,
            label,
            owner,
            subregistry,
            resolver,
            duration,
            paymentToken,
            referrer,
            base,
            premium
        );
    }

    /// @inheritdoc IETHRegistrar
    function renew(
        string memory label,
        uint64 duration,
        IERC20 paymentToken,
        bytes32 referrer
    ) external {
        (uint256 tokenId, IRegistryDatastore.Entry memory entry) = REGISTRY.getNameData(label);
        uint64 oldExpiry = entry.expiry;
        if (_isAvailable(oldExpiry)) {
            revert NameNotRegistered(label);
        }
        uint64 expires = oldExpiry + duration;
        (uint256 base, ) = rentPrice(
            label,
            REGISTRY.latestOwnerOf(tokenId),
            duration,
            paymentToken
        ); // reverts if !isValid or !isPaymentToken or duration is 0
        require(paymentToken.transferFrom(_msgSender(), BENEFICIARY, base)); // reverts if payment failed
        REGISTRY.renew(tokenId, expires);
        emit NameRenewed(tokenId, label, duration, expires, paymentToken, referrer, base);
    }

    /// @inheritdoc IRentPriceOracle
    function isPaymentToken(IERC20 paymentToken) external view returns (bool) {
        return rentPriceOracle.isPaymentToken(paymentToken);
    }

    /// @inheritdoc IRentPriceOracle
    function isValid(string memory label) external view returns (bool) {
        return rentPriceOracle.isValid(label);
    }

    /// @inheritdoc IETHRegistrar
    /// @dev Does not check if normalized or valid.
    function isAvailable(string memory label) external view returns (bool) {
        (, IRegistryDatastore.Entry memory entry) = REGISTRY.getNameData(label);
        uint64 expiry = entry.expiry;
        return _isAvailable(expiry);
    }

    /// @inheritdoc IETHRegistrar
    function commitmentAt(bytes32 commitment) external view returns (uint64) {
        return _commitTime[commitment];
    }

    /// @inheritdoc IRentPriceOracle
    function rentPrice(
        string memory label,
        address owner,
        uint64 duration,
        IERC20 paymentToken
    ) public view returns (uint256 base, uint256 premium) {
        return rentPriceOracle.rentPrice(label, owner, duration, paymentToken);
    }

    /// @inheritdoc IETHRegistrar
    function makeCommitment(
        string memory label,
        address owner,
        bytes32 secret,
        IRegistry subregistry,
        address resolver,
        uint64 duration,
        bytes32 referrer
    ) public pure override returns (bytes32) {
        return
            keccak256(abi.encode(label, owner, secret, subregistry, resolver, duration, referrer));
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    /// @dev Assert `commitment` is timely, then delete it.
    function _consumeCommitment(bytes32 commitment) internal {
        uint64 t = uint64(block.timestamp);
        uint64 t0 = _commitTime[commitment];
        uint64 tMin = t0 + MIN_COMMITMENT_AGE;
        if (t < tMin) {
            revert CommitmentTooNew(commitment, tMin, t);
        }
        uint64 tMax = t0 + MAX_COMMITMENT_AGE;
        if (t >= tMax) {
            revert CommitmentTooOld(commitment, tMax, t);
        }
        delete _commitTime[commitment];
    }

    /// @dev Internal logic for registration availability.
    function _isAvailable(uint256 expiry) internal view returns (bool) {
        return block.timestamp >= expiry;
    }
}
