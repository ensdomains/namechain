// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IETHRegistrar} from "./IETHRegistrar.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {IERC1155Singleton} from "../common/IERC1155Singleton.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {ITokenPriceOracle} from "./ITokenPriceOracle.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {EnhancedAccessControl, LibEACBaseRoles} from "../common/EnhancedAccessControl.sol";
import {LibRegistryRoles} from "../common/LibRegistryRoles.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ETHRegistrar is IETHRegistrar, EnhancedAccessControl {
    using SafeERC20 for IERC20;
    uint256 private constant REGISTRATION_ROLE_BITMAP = 
        LibRegistryRoles.ROLE_SET_SUBREGISTRY | 
        LibRegistryRoles.ROLE_SET_SUBREGISTRY_ADMIN | 
        LibRegistryRoles.ROLE_SET_RESOLVER | 
        LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN;

    uint256 public constant MIN_REGISTRATION_DURATION = 28 days;

    error MaxCommitmentAgeTooLow();
    error UnexpiredCommitmentExists(bytes32 commitment);
    error DurationTooShort(uint64 duration, uint256 minDuration);
    error CommitmentTooNew(bytes32 commitment, uint256 validFrom, uint256 blockTimestamp);
    error CommitmentTooOld(bytes32 commitment, uint256 validTo, uint256 blockTimestamp);
    error NameNotAvailable(string name);
    error InsufficientValue(uint256 required, uint256 provided);
    error TokenNotSupported(address token);
    /// @dev Thrown when duration would overflow when added to expiry time
    error DurationOverflow(uint64 expiry, uint64 duration);

    IPermissionedRegistry public immutable registry;
    ITokenPriceOracle public immutable tokenPriceOracle;
    uint256 public immutable minCommitmentAge;
    uint256 public immutable maxCommitmentAge;
    address public immutable beneficiary;

    mapping(bytes32 => uint256) public commitments;    

    constructor(address _registry, ITokenPriceOracle _prices, uint256 _minCommitmentAge, uint256 _maxCommitmentAge, address _beneficiary) {
        _grantRoles(ROOT_RESOURCE, LibEACBaseRoles.ALL_ROLES, _msgSender(), true);

        registry = IPermissionedRegistry(_registry);

        if (_maxCommitmentAge <= _minCommitmentAge) {
            revert MaxCommitmentAgeTooLow();
        }

        tokenPriceOracle = _prices;
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
        beneficiary = _beneficiary;
    }

    /**
     * @dev Check if a name is valid.
     * @param name The name to check.
     * @return True if the name is valid, false otherwise.
     */
    function valid(string memory name) public pure returns (bool) {
        return bytes(name).length >= 3;
    }

    /**
     * @dev Check if a name is available.
     * @param name The name to check.
     * @return True if the name is available, false otherwise.
     */
    function available(string calldata name) external view returns (bool) {
        (, uint64 expiry, ) = registry.getNameData(name);
        return expiry < block.timestamp;
    }


    /**
     * @dev Get the price to register or renew a name.
     * @param name The name to get the price for.
     * @param duration The duration of the registration or renewal.
     * @return price The price to register or renew the name.
     */ 
    function rentPrice(string memory name, uint256 duration) public view override returns (ITokenPriceOracle.Price memory price) {
        (, uint64 expiry, ) = registry.getNameData(name);
        price = tokenPriceOracle.price(name, uint256(expiry), duration);
    }

    /**
     * @dev Check the price of a name and get the required token amount.
     * @param name The name to check the price for.
     * @param duration The duration of the registration or renewal.
     * @param token The ERC20 token address.
     * @return tokenAmount The amount of tokens required.
     */
    function checkPrice(string memory name, uint256 duration, address token) public view returns (uint256 tokenAmount) {
        if (!tokenPriceOracle.getTokenConfig(token).enabled) {
            revert TokenNotSupported(token);
        }

        (, uint64 expiry, ) = registry.getNameData(name);
        tokenAmount = tokenPriceOracle.priceInToken(name, uint256(expiry), duration, token);
    }    


    /**
     * @dev Make a commitment for a name.
     * @param name The name to commit.
     * @param owner The address of the owner of the name.
     * @param secret The secret of the name.
     * @param subregistry The registry to use for the commitment.
     * @param resolver The resolver to use for the commitment.
     * @param duration The duration of the commitment.
     * @return The commitment.
     */
    function makeCommitment(
        string memory name,
        address owner,
        bytes32 secret,
        address subregistry,
        address resolver,
        uint64 duration
    ) public pure override returns (bytes32) {        
        return
            keccak256(
                abi.encode(
                    name,
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
     * @dev Register a name with ERC20 token payment.
     * @param name The name to register.
     * @param owner The owner of the name.
     * @param secret The secret of the name.
     * @param subregistry The subregistry to register the name in.
     * @param resolver The resolver to use for the registration.
     * @param duration The duration of the registration.
     * @param token The ERC20 token address for payment.
     * @return tokenId The token ID of the registered name.
     */
    function register(
        string calldata name,
        address owner,
        bytes32 secret,
        IRegistry subregistry,
        address resolver,
        uint64 duration,
        address token
    ) external returns (uint256 tokenId) {
        if (!valid(name)) {
            revert NameNotAvailable(name);
        }
        
        // CHECKS: Validate commitment and get pricing (external calls for validation only)
        _consumeCommitment(name, duration, makeCommitment(name, owner, secret, address(subregistry), resolver, duration));
        uint64 expiry = uint64(block.timestamp) + duration;
        // Get USD pricing breakdown
        ITokenPriceOracle.Price memory usdPrice = tokenPriceOracle.price(name, expiry, duration);
        
        // Convert to token amount for payment and handle transfer
        {
            uint256 tokenAmount = tokenPriceOracle.priceInToken(name, expiry, duration, token);
            // EFFECTS: Handle payment BEFORE state changes
            IERC20(token).safeTransferFrom(msg.sender, beneficiary, tokenAmount);
        }

        // INTERACTIONS: Register name only after successful payment
        tokenId = registry.register(name, owner, subregistry, resolver, REGISTRATION_ROLE_BITMAP, expiry);
        
        emit NameRegistered(name, owner, subregistry, resolver, duration, tokenId, usdPrice.base, usdPrice.premium);
    }

    /**
     * @dev Renew a name with ERC20 token payment.
     * @param name The name to renew.
     * @param duration The duration of the renewal.
     * @param token The ERC20 token address for payment.
     */
    function renew(string calldata name, uint64 duration, address token) external {
        if (!valid(name)) {
            revert NameNotAvailable(name);
        }
        
        // CHECKS: Get current data and validate pricing
        (uint256 tokenId, uint64 expiry, ) = registry.getNameData(name);
        
        // Check for overflow before any state changes
        if (expiry > type(uint64).max - duration) {
            revert DurationOverflow(expiry, duration);
        }
        uint64 newExpiry = expiry + duration;
        
        // Get USD pricing breakdown
        ITokenPriceOracle.Price memory usdPrice = tokenPriceOracle.price(name, uint256(expiry), duration);
        
        // Convert to token amount for payment and handle transfer
        {
            uint256 tokenAmount = tokenPriceOracle.priceInToken(name, uint256(expiry), duration, token);
            // EFFECTS: Handle payment BEFORE state changes
            IERC20(token).safeTransferFrom(msg.sender, beneficiary, tokenAmount);
        }
        
        // INTERACTIONS: Renew name only after successful payment
        registry.renew(tokenId, newExpiry);
        
        emit NameRenewed(name, duration, tokenId, newExpiry, usdPrice.base);
    }


    function supportsInterface(bytes4 interfaceID) public view override(EnhancedAccessControl) returns (bool) {
        return interfaceID == type(IETHRegistrar).interfaceId || super.supportsInterface(interfaceID);
    }

    /* Internal functions */

    function _consumeCommitment(
        string memory name,
        uint64 duration,
        bytes32 commitment
    ) internal {
        // Require an old enough commitment.
        uint256 thisCommitmentValidFrom = commitments[commitment] + minCommitmentAge;
        if (thisCommitmentValidFrom > block.timestamp) {
            revert CommitmentTooNew(commitment, thisCommitmentValidFrom, block.timestamp);
        }

        // Commit must not be too old
        uint256 thisCommitmentValidTo = commitments[commitment] + maxCommitmentAge;
        if (thisCommitmentValidTo <= block.timestamp) {
            revert CommitmentTooOld(commitment, thisCommitmentValidTo, block.timestamp);
        }

        // Name must be available
        if (!this.available(name)) {
            revert NameNotAvailable(name);
        }

        if (duration < MIN_REGISTRATION_DURATION) {
            revert DurationTooShort(duration, MIN_REGISTRATION_DURATION);
        }

        delete (commitments[commitment]);
    }


}