// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IETHRegistrar} from "./IETHRegistrar.sol";
import {IRegistry} from "./IRegistry.sol";
import {IERC1155Singleton} from "./IERC1155Singleton.sol";
import {IETHRegistry} from "./IETHRegistry.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {NameUtils} from "../utils/NameUtils.sol";

contract ETHRegistrar is IETHRegistrar, AccessControl {
    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    uint256 public constant MIN_REGISTRATION_DURATION = 28 days;
    uint64 private constant MAX_EXPIRY = type(uint64).max;

    error MaxCommitmentAgeTooLow();
    error MaxCommitmentAgeTooHigh();
    error UnexpiredCommitmentExists(bytes32 commitment);
    error DurationTooShort(uint64 duration);
    error CommitmentTooNew(bytes32 commitment);
    error CommitmentTooOld(bytes32 commitment);
    error NameNotAvailable(string name);
    error InsufficientValue();

    IETHRegistry public immutable registry;
    IPriceOracle public immutable prices;
    uint256 public immutable minCommitmentAge;
    uint256 public immutable maxCommitmentAge;

    mapping(bytes32 => uint256) public commitments;    

    constructor(address _registry, IPriceOracle _prices, uint256 _minCommitmentAge, uint256 _maxCommitmentAge) {
        registry = IETHRegistry(_registry);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        if (_maxCommitmentAge <= _minCommitmentAge) {
            revert MaxCommitmentAgeTooLow();
        }

        if (_maxCommitmentAge > block.timestamp) {
            revert MaxCommitmentAgeTooHigh();
        }

        prices = _prices;
        minCommitmentAge = _minCommitmentAge;
        maxCommitmentAge = _maxCommitmentAge;
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
        address subregistry = address(registry.getSubregistry(name));
        return subregistry == address(0);
    }


    /**
     * @dev Get the price to register or renew a name.
     * @param name The name to get the price for.
     * @param duration The duration of the registration or renewal.
     * @return price The price to register or renew the name.
     */ 
    function rentPrice(string memory name, uint256 duration) public view override returns (IPriceOracle.Price memory price) {
        (uint96 expiry, ) = registry.nameData(NameUtils.labelToTokenId(name));
        price = prices.price(name, uint256(expiry), duration);
    }    


    /**
     * @dev Make a commitment for a name.
     * @param name The name to commit.
     * @param owner The address of the owner of the name.
     * @param secret The secret of the name.
     * @param subregistry The registry to use for the commitment.
     * @param flags The flags to use for the commitment.
     * @param duration The duration of the commitment.
     * @return The commitment.
     */
    function makeCommitment(
        string memory name,
        address owner,
        bytes32 secret,
        address subregistry,
        uint96 flags,
        uint64 duration
    ) public pure override returns (bytes32) {        
        return
            keccak256(
                abi.encode(
                    name,
                    owner,
                    secret,
                    subregistry,
                    flags,
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
    }



    /**
     * @dev Register a name.
     * @param name The name to register.
     * @param owner The owner of the name.
     * @param subregistry The subregistry to register the name in.
     * @param flags The flags to set on the name.   
     * @param duration The duration of the registration.
     * @return tokenId The token ID of the registered name.
     */
    function register(
        string calldata name,
        address owner,
        IRegistry subregistry,
        uint96 flags,
        uint64 duration
    ) external payable onlyRole(CONTROLLER_ROLE) returns (uint256 tokenId) {
        IPriceOracle.Price memory price = rentPrice(name, duration);
        uint256 totalPrice = price.base + price.premium;
        if (msg.value < totalPrice) {
            revert InsufficientValue();
        }

        _consumeCommitment(name, duration, makeCommitment(name, owner, bytes32(0), address(subregistry), flags, duration));

        tokenId = registry.register(name, owner, subregistry, flags, uint64(block.timestamp) + duration);

        if (msg.value > totalPrice) {
            payable(msg.sender).transfer(msg.value - totalPrice);
        }

        emit NameRegistered(name, owner, subregistry, flags, duration, tokenId);
    }

    /**
     * @dev Renew a name.
     * @param name The name to renew.
     * @param duration The duration of the renewal.
     */
    function renew(string calldata name, uint64 duration) external payable onlyRole(CONTROLLER_ROLE) {
        IPriceOracle.Price memory price = rentPrice(name, duration);
        uint256 totalPrice = price.base + price.premium;
        if (msg.value < totalPrice) {
            revert InsufficientValue();
        }

        uint256 tokenId = NameUtils.labelToTokenId(name);

        (uint64 expiry, ) = registry.nameData(tokenId);

        registry.renew(tokenId, expiry + duration);

        if (msg.value > totalPrice) {
            payable(msg.sender).transfer(msg.value - totalPrice);
        }

        emit NameRenewed(name, duration, tokenId);
    }


    function supportsInterface(bytes4 interfaceID) public view override(AccessControl) returns (bool) {
        return interfaceID == type(IETHRegistrar).interfaceId || AccessControl.supportsInterface(interfaceID);
    }

    /* Internal functions */

    function _consumeCommitment(
        string memory name,
        uint64 duration,
        bytes32 commitment
    ) internal {
        // Require an old enough commitment.
        if (commitments[commitment] + minCommitmentAge > block.timestamp) {
            revert CommitmentTooNew(commitment);
        }

        // Commit must not be too old
        if (commitments[commitment] + maxCommitmentAge <= block.timestamp) {
            revert CommitmentTooOld(commitment);
        }

        // Name must be available
        if (!this.available(name)) {
            revert NameNotAvailable(name);
        }

        if (duration < MIN_REGISTRATION_DURATION) {
            revert DurationTooShort(duration);
        }

        delete (commitments[commitment]);
    }
}
