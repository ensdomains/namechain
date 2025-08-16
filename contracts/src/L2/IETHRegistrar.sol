// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistry} from "../common/IRegistry.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";


uint8 constant PRICE_DECIMALS = 12;

/**
 * @dev Interface for the ETH Registrar.
 */
interface IETHRegistrar {

	error NameNotAvailable(string label);
	error NameNotValid(string label);
	error NameNotRenewable(string label);
	
    error PaymentTokenNotSupported(IERC20Metadata paymentToken);
	
    /// @dev Thrown when duration would overflow when added to expiry time
    error DurationOverflow(uint64 expiry, uint64 duration);

    error InvalidOwner();
	
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
    
    event PaymentTokenChanged(IERC20Metadata paymentToken, bool supported);

    /**
     * @dev Emitted when a name is registered.
     *
     * @param label The name that was registered.
     * @param owner The address of the owner of the name.
     * @param subregistry The registry used for the registration.
     * @param resolver The resolver used for the registration.
     * @param duration The duration of the registration.
     * @param tokenId The ID of the newly registered name.
     * @param base The base cost component in USD (USD_DECIMALS precision).
     * @param premium The premium cost component in USD (USD_DECIMALS precision).
     */
    event NameRegistered(
        string label,
        address owner,
        IRegistry subregistry,
        address resolver,
        uint64 duration,
        uint256 tokenId,
		IERC20Metadata paymentToken,
        uint256 base,
        uint256 premium
    );

    /**
     * @dev Emitted when a name is renewed.
     *
     * @param label The name that was renewed.
     * @param duration The duration of the renewal.
     * @param tokenId The ID of the renewed name.
     * @param newExpiry The new expiry of the name.
     * @param base The cost in USD (USD_DECIMALS precision). Renewals have no premium.
     */
    event NameRenewed(
        string label,
        uint64 duration,
        uint256 tokenId,
        uint64 newExpiry,
		IERC20Metadata paymentToken,
        uint256 base
    );

    /**
     * @dev Emitted when a commitment is made.
     *
     * @param commitment The commitment that was made.
     */
    event CommitmentMade(bytes32 commitment);

    /**
     * @dev Returns true if the specified name is available for registration.
     *
     * @param name The name to check.
     *
     * @return True if the name is available, false otherwise.
     */
    function isAvailable(string memory name) external view returns (bool);

    /**
     * @dev Check if a name is valid.
     * @param name The name to check.
     * @return True if the name is valid, false otherwise.
     */
    function isValid(string memory name) external view returns (bool);

	/// @dev Check if `paymentToken` may be used for payment.
	/// @param paymentToken The ERC20 to check.
	/// @return `true` if `paymentToken` is supported.
	function isPaymentToken(IERC20Metadata paymentToken) external view returns (bool);

	/// @dev Number of decimals for prices and rates.
	function priceDecimals() external view returns (uint8);

	/// @dev Get rent price for `name` with `duration`.
	/// @param label The name to price.
	/// @param duration The duration to price, in seconds.
	/// @return base The base price.
	/// @return premium The premium price.
	function rentPrice(
        string memory label,
        uint64 duration
    ) external view returns (uint256 base, uint256 premium);

    /**
     * @dev Check the price of a name and get the required token amount.
     * @param label The name to check the price for.
     * @param duration The duration of the registration or renewal.
     * @param paymentToken The ERC20 token address.
	/// @return base The base price, in quantity of token.
	/// @return premium The premium price, in quantity of token.
     */
    function rentPrice(
        string memory label,
        uint64 duration,
        IERC20Metadata paymentToken
    ) external view returns (uint256 base, uint256 premium);

    /**
     * @dev Make a commitment for a name.
     *
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
        IRegistry subregistry,
        address resolver,
        uint64 duration
    ) external pure returns (bytes32);

    /**
     * @dev Commit a commitment.
     *
     * @param commitment The commitment to commit.
     */
    function commit(bytes32 commitment) external;

    /**
     * @dev Register a name with ERC20 token payment.
     *
     * @param label The name to register.
     * @param owner The address of the owner of the name.
     * @param secret The secret of the name.
     * @param subregistry The registry to use for the registration.
     * @param resolver The resolver to use for the registration.
     * @param duration The duration of the registration.
     * @param paymentToken The ERC20 token address for payment.
     *
     * @return The ID of the newly registered name.
     */
    function register(
        string memory label,
        address owner,
        bytes32 secret,
        IRegistry subregistry,
        address resolver,
        uint64 duration,
        IERC20Metadata paymentToken
    ) external returns (uint256);

    /**
     * @dev Renew a name with ERC20 token payment.
     *
     * @param label The name to renew.
     * @param duration The duration of the renewal.
     * @param paymentToken The ERC20 token address for payment.
     */
    function renew(
        string memory label,
        uint64 duration,
        IERC20Metadata paymentToken
    ) external;
}
