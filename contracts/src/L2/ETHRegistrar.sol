// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IETHRegistrar} from "./IETHRegistrar.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {IERC1155Singleton} from "../common/IERC1155Singleton.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {EnhancedAccessControl} from "../common/EnhancedAccessControl.sol";
import {RegistryRolesMixin} from "../common/RegistryRolesMixin.sol";

contract ETHRegistrar is
    IETHRegistrar,
    EnhancedAccessControl,
    RegistryRolesMixin
{
    uint256 private constant REGISTRATION_ROLE_BITMAP =
        ROLE_SET_SUBREGISTRY |
            ROLE_SET_SUBREGISTRY_ADMIN |
            ROLE_SET_RESOLVER |
            ROLE_SET_RESOLVER_ADMIN;

    uint256 private constant ROLE_SET_PRICE_ORACLE = 1 << 0;
    uint256 private constant ROLE_SET_PRICE_ORACLE_ADMIN =
        ROLE_SET_PRICE_ORACLE << 128;

    uint256 private constant ROLE_SET_COMMITMENT_AGES = 1 << 1;
    uint256 private constant ROLE_SET_COMMITMENT_AGES_ADMIN =
        ROLE_SET_COMMITMENT_AGES << 128;

    uint256 public constant MIN_REGISTRATION_DURATION = 28 days;

    error MaxCommitmentAgeTooLow();
    error UnexpiredCommitmentExists(bytes32 commitment);
    error DurationTooShort(uint64 duration, uint256 minDuration);
    error CommitmentTooNew(
        bytes32 commitment,
        uint256 validFrom,
        uint256 blockTimestamp
    );
    error CommitmentTooOld(
        bytes32 commitment,
        uint256 validTo,
        uint256 blockTimestamp
    );
    error NameNotAvailable(string name);
    error InsufficientValue(uint256 required, uint256 provided);

    IPermissionedRegistry public immutable registry;
    IPriceOracle public prices;
    uint256 public minCommitmentAge;
    uint256 public maxCommitmentAge;

    mapping(bytes32 => uint256) public commitments;

    constructor(
        address _registry,
        IPriceOracle _prices,
        uint256 _minCommitmentAge,
        uint256 _maxCommitmentAge
    ) {
        _grantRoles(ROOT_RESOURCE, ALL_ROLES, _msgSender(), true);

        registry = IPermissionedRegistry(_registry);

        if (_maxCommitmentAge <= _minCommitmentAge) {
            revert MaxCommitmentAgeTooLow();
        }

        prices = _prices;
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
    }

    /**
     * @dev Check if a name is valid.
     * @param label The name to check.
     * @return True if the name is valid, false otherwise.
     */
    function valid(string memory label) public pure returns (bool) {
        return bytes(label).length >= 3 && NameUtils.isValidLabel(label);
    }

    /**
     * @dev Check if a name is available.
     * @param label The name to check.
     * @return True if the name is available, false otherwise.
     */
    function available(string calldata label) external view returns (bool) {
        (, uint64 expiry, ) = registry.getNameData(label);
        return expiry < block.timestamp;
    }

    /**
     * @dev Get the price to register or renew a name.
     * @param label The name to get the price for.
     * @param duration The duration of the registration or renewal.
     * @return price The price to register or renew the name.
     */
    function rentPrice(
        string memory label,
        uint256 duration
    ) public view override returns (IPriceOracle.Price memory price) {
        (, uint64 expiry, ) = registry.getNameData(label);
        price = prices.price(label, uint256(expiry), duration);
    }

    /**
     * @dev Make a commitment for a name.
     * @param label The name to commit.
     * @param owner The address of the owner of the name.
     * @param secret The secret of the name.
     * @param subregistry The registry to use for the commitment.
     * @param resolver The resolver to use for the commitment.
     * @param duration The duration of the commitment.
     * @return The commitment.
     */
    function makeCommitment(
        string memory label,
        address owner,
        bytes32 secret,
        address subregistry,
        address resolver,
        uint64 duration
    ) public pure override returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    label,
                    owner,
                    secret,
                    subregistry,
                    resolver,
                    duration
                )
            );
    }

    /**
     * @dev Commit a commitment.
     * @param commitment The commitment to commit.
     */
    function commit(bytes32 commitment) public override {
        if (commitments[commitment] + maxCommitmentAge >= block.timestamp) {
            revert UnexpiredCommitmentExists(commitment);
        }
        commitments[commitment] = block.timestamp;

        emit CommitmentMade(commitment);
    }

    /**
     * @dev Register a name.
     * @param label The name to register.
     * @param owner The owner of the name.
     * @param secret The secret of the name.
     * @param subregistry The subregistry to register the name in.
     * @param resolver The resolver to use for the registration.
     * @param duration The duration of the registration.
     * @return tokenId The token ID of the registered name.
     */
    function register(
        string calldata label,
        address owner,
        bytes32 secret,
        IRegistry subregistry,
        address resolver,
        uint64 duration
    ) external payable returns (uint256 tokenId) {
        uint256 totalPrice = checkPrice(label, duration);

        _consumeCommitment(
            label,
            duration,
            makeCommitment(
                label,
                owner,
                secret,
                address(subregistry),
                resolver,
                duration
            )
        );

        uint64 expiry = uint64(block.timestamp) + duration;
        tokenId = registry.register(
            label,
            owner,
            subregistry,
            resolver,
            REGISTRATION_ROLE_BITMAP,
            expiry
        );

        if (msg.value > totalPrice) {
            payable(msg.sender).transfer(msg.value - totalPrice);
        }

        emit NameRegistered(
            label,
            owner,
            subregistry,
            resolver,
            duration,
            tokenId
        );
    }

    /**
     * @dev Renew a name.
     * @param label The name to renew.
     * @param duration The duration of the renewal.
     */
    function renew(string calldata label, uint64 duration) external payable {
        uint256 totalPrice = checkPrice(label, duration);

        (uint256 tokenId, uint64 expiry, ) = registry.getNameData(label);

        registry.renew(tokenId, expiry + duration);

        if (msg.value > totalPrice) {
            payable(msg.sender).transfer(msg.value - totalPrice);
        }

        uint64 newExpiry = registry.getExpiry(tokenId);

        emit NameRenewed(label, duration, tokenId, newExpiry);
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(EnhancedAccessControl) returns (bool) {
        return
            interfaceId == type(IETHRegistrar).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function setPriceOracle(
        IPriceOracle _prices
    ) external onlyRoles(ROOT_RESOURCE, ROLE_SET_PRICE_ORACLE) {
        prices = _prices;
    }

    function setCommitmentAges(
        uint256 _minCommitmentAge,
        uint256 _maxCommitmentAge
    ) external onlyRoles(ROOT_RESOURCE, ROLE_SET_COMMITMENT_AGES) {
        if (_maxCommitmentAge <= _minCommitmentAge) {
            revert MaxCommitmentAgeTooLow();
        }
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
    }

    /* Internal functions */

    function _consumeCommitment(
        string memory label,
        uint64 duration,
        bytes32 commitment
    ) internal {
        // Require an old enough commitment.
        uint256 thisCommitmentValidFrom = commitments[commitment] +
            minCommitmentAge;
        if (thisCommitmentValidFrom > block.timestamp) {
            revert CommitmentTooNew(
                commitment,
                thisCommitmentValidFrom,
                block.timestamp
            );
        }

        // Commit must not be too old
        uint256 thisCommitmentValidTo = commitments[commitment] +
            maxCommitmentAge;
        if (thisCommitmentValidTo <= block.timestamp) {
            revert CommitmentTooOld(
                commitment,
                thisCommitmentValidTo,
                block.timestamp
            );
        }

        // Name must be available
        if (!this.available(label)) {
            revert NameNotAvailable(label);
        }

        if (duration < MIN_REGISTRATION_DURATION) {
            revert DurationTooShort(duration, MIN_REGISTRATION_DURATION);
        }

        delete (commitments[commitment]);
    }

    /**
     * @dev Check the price of a name and revert if insufficient value is provided.
     * @param label The name to check the price for.
     * @param duration The duration of the registration.
     * @return totalPrice The total price of the registration.
     */
    function checkPrice(
        string memory label,
        uint64 duration
    ) private view returns (uint256 totalPrice) {
        IPriceOracle.Price memory price = rentPrice(label, duration);
        totalPrice = price.base + price.premium;
        if (msg.value < totalPrice) {
            revert InsufficientValue(totalPrice, msg.value);
        }
    }
}
