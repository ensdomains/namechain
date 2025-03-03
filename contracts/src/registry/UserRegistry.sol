// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/console2.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

import {BaseRegistry} from "./BaseRegistry.sol";
import {IRegistry} from "./IRegistry.sol";
import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {PermissionedRegistry} from "./PermissionedRegistry.sol";
import {NameUtils} from "../utils/NameUtils.sol";

/**
 * @title UserRegistry
 * @dev Default registry for user names with enhanced migration support for wrapped names.
 * This registry handles creation and management of subnames, with special functionality
 * for migrating names from the ENSv1 Name Wrapper on L1.
 */
contract UserRegistry is
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PermissionedRegistry(IRegistryDatastore(address(0)))
{
    // =================== Storage Variables ===================

    bytes32 public constant MIGRATION_CONTROLLER_ROLE = keccak256("MIGRATION_CONTROLLER_ROLE");

    IRegistry public parent;
    string public label;
    uint64 public defaultDuration;

    // Storage gap for future upgrades
    // ref: https://docs.openzeppelin.com/contracts/3.x/upgradeable#storage_gaps
    uint256[50] private __gap;

    // =================== Errors ===================

    error NameExpired(uint256 tokenId);
    error CannotReduceExpiration(uint64 oldExpiration, uint64 newExpiration);

    // =================== Events ===================

    event SubnameCreated(string indexed label, address indexed owner, uint64 expires);
    event SubnameRenewed(uint256 indexed tokenId, uint64 newExpiration);
    event MigratedNameImported(string indexed label, address owner, uint96 flags, uint64 expires);
    event BatchMigrationCompleted(uint256 count);

    // =================== Context Overrides ===================

    /**
     * @dev Override _msgSender() to resolve the conflict between Context implementations
     */
    function _msgSender() internal view virtual override(Context, ContextUpgradeable) returns (address) {
        console2.log("_msgSender called:");
        console2.logAddress(msg.sender);
        return msg.sender;
    }

    /**
     * @dev Override _msgData() to resolve the conflict between Context implementations
     */
    function _msgData() internal view virtual override(Context, ContextUpgradeable) returns (bytes calldata) {
        return msg.data;
    }

    /**
     * @dev Override _contextSuffixLength() to resolve the conflict between Context implementations
     */
    function _contextSuffixLength() internal view virtual override(Context, ContextUpgradeable) returns (uint256) {
        return 0;
    }

    // =================== Modifiers ===================

    /**
     * @dev Modifier to restrict functions to the name owner
     */
    modifier onlyNameOwner() {
        uint256 tokenId = (uint256(keccak256(bytes(label))) & ~uint256(FLAGS_MASK));
        address owner = parent.ownerOf(tokenId);
        if (owner != _msgSender()) {
            revert AccessDenied(0, owner, _msgSender());
        }
        _;
    }

    // =================== Initialization ===================

    /**
     * @dev Initializes the contract.
     */
    function initialize(IRegistry _parent, string memory _label, IRegistryDatastore _datastore, address _owner)
        public
        initializer
    {
        __UUPSUpgradeable_init();
        __AccessControl_init();

        // Initialize the PermissionedRegistry with the datastore
        datastore = _datastore;

        // Grant admin role to the owner
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);

        parent = _parent;
        label = _label;
        defaultDuration = 365 days;
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract.
     * Called by {upgradeTo} and {upgradeToAndCall}.
     */
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // =================== URI ===================

    /**
     * @dev Custom URI function for token metadata
     */
    function uri(uint256 /*id*/ ) public pure override returns (string memory) {
        return "";
    }

    // =================== Subname Management ===================

    /**
     * @dev Create a new subname
     * @param _label The subname label
     * @param owner The owner of the new subname
     * @param registry The registry to use for the subname
     * @param flags Flags to set on the subname
     * @return tokenId The token ID of the new subname
     */
    function mint(string calldata _label, address owner, IRegistry registry, uint96 flags)
        external
        virtual
        onlyNameOwner
        returns (uint256 tokenId)
    {
        // Calculate the token ID based on the label hash
        tokenId = uint256(keccak256(bytes(_label)));

        // Apply flags to the lowest bits of the token ID
        tokenId = (tokenId & ~uint256(FLAGS_MASK)) | (flags & FLAGS_MASK);

        // Apply storage flags with expiration
        uint96 storageFlags = (flags & FLAGS_MASK) | (uint96(uint64(block.timestamp + defaultDuration)) << 32);

        // Create the token and set its registry
        _mint(owner, tokenId, 1, "");
        datastore.setSubregistry(tokenId, address(registry), storageFlags);

        emit NewSubname(_label);
        emit SubnameCreated(_label, owner, uint64(block.timestamp + defaultDuration));

        return tokenId;
    }

    /**
     * @dev Remove a subname from the registry
     * @param tokenId The token ID to burn
     */
    function burn(uint256 tokenId) external onlyNameOwner withSubregistryFlags(tokenId, FLAG_SUBREGISTRY_LOCKED, 0) {
        address owner = ownerOf(tokenId);
        _burn(owner, tokenId, 1);
        datastore.setSubregistry(tokenId, address(0), 0);
    }

    /**
     * @dev Renew a subname
     * @param tokenId The token ID to renew
     * @param duration The duration to extend the name for
     */
    function renew(uint256 tokenId, uint64 duration) external onlyNameOwner {
        (address subregistry, uint96 flags) = datastore.getSubregistry(tokenId);

        // Extract current expiration
        uint64 oldExpiration = _extractExpiry(flags);

        // Ensure name hasn't expired
        if (oldExpiration < block.timestamp) {
            revert NameExpired(tokenId);
        }

        console2.log("oldExpiration");
        console2.logUint(oldExpiration);
        console2.log("block");
        console2.logUint(block.timestamp);

        // Calculate new expiration
        uint64 newExpiry = oldExpiration + duration;

        if (newExpiry < oldExpiration) {
            revert CannotReduceExpiration(oldExpiration, newExpiry);
        }

        // Update with new expiration while preserving flags
        datastore.setSubregistry(tokenId, subregistry, (flags & FLAGS_MASK) | (uint96(newExpiry) << 32));

        emit SubnameRenewed(tokenId, newExpiry);
    }

    // =================== Flag Operations ===================

    /**
     * @dev Check if a subname is locked
     * @param tokenId The token ID to check
     * @return Whether the subname is locked
     */
    function locked(uint256 tokenId) external view returns (bool) {
        (, uint96 flags) = datastore.getSubregistry(tokenId);
        return flags & FLAG_SUBREGISTRY_LOCKED != 0;
    }

    /**
     * @dev Lock a subname
     * @param tokenId The token ID to lock
     */
    function lock(uint256 tokenId) external onlyTokenOwner(tokenId) {
        (address subregistry, uint96 flags) = datastore.getSubregistry(tokenId);
        datastore.setSubregistry(tokenId, subregistry, flags | FLAG_SUBREGISTRY_LOCKED);
    }

    /**
     * @dev Lock the resolver for a subname
     * @param tokenId The token ID to lock resolver for
     */
    function lockResolver(uint256 tokenId) external onlyTokenOwner(tokenId) {
        (address subregistry, uint96 flags) = datastore.getSubregistry(tokenId);
        datastore.setSubregistry(tokenId, subregistry, flags | FLAG_RESOLVER_LOCKED);
    }

    /**
     * @dev Lock flags for a subname
     * @param tokenId The token ID to lock flags for
     */
    function lockFlags(uint256 tokenId) external onlyTokenOwner(tokenId) {
        (address subregistry, uint96 flags) = datastore.getSubregistry(tokenId);
        datastore.setSubregistry(tokenId, subregistry, flags | FLAG_FLAGS_LOCKED);
    }

    /**
     * @dev Set the default duration for new names
     * @param _defaultDuration The new default duration in seconds
     */
    function setDefaultDuration(uint64 _defaultDuration) external onlyNameOwner {
        defaultDuration = _defaultDuration;
    }

    /**
     * @dev Get expiry time for a subname
     * @param tokenId The token ID
     * @return expiry The expiration timestamp
     */
    function getExpiry(uint256 tokenId) external view returns (uint64 expiry) {
        (, uint96 flags) = datastore.getSubregistry(tokenId);
        return uint64(flags >> 32);
    }

    // =================== Migration ===================

    /**
     * @dev Add a migration controller
     * @param controller The migration controller address
     */
    function addMigrationController(address controller) external onlyNameOwner {
        grantRole(MIGRATION_CONTROLLER_ROLE, controller);
    }

    /**
     * @dev Remove a migration controller
     * @param controller The migration controller address
     */
    function removeMigrationController(address controller) external onlyNameOwner {
        revokeRole(MIGRATION_CONTROLLER_ROLE, controller);
    }

    /**
     * @dev Import a migrated name from L1 Name Wrapper
     * This function is called by the L2MigrationController after receiving verified data from L1
     * @param _label The label for the migrated name
     * @param owner The owner of the name
     * @param registry The registry to use
     * @param flags Flags corresponding to Name Wrapper fuses
     * @param expires Expiration timestamp
     * @return tokenId The token ID of the migrated name
     */
    function importMigratedName(string calldata _label, address owner, IRegistry registry, uint96 flags, uint64 expires)
        public
        onlyRole(MIGRATION_CONTROLLER_ROLE)
        returns (uint256 tokenId)
    {
        tokenId = uint256(keccak256(bytes(_label)));

        // Set expiration and flags
        flags = (flags & FLAGS_MASK) | (uint96(expires) << 32);

        // Mint the token
        _mint(owner, tokenId, 1, "");
        datastore.setSubregistry(tokenId, address(registry), flags);

        emit NewSubname(_label);
        emit MigratedNameImported(_label, owner, flags & FLAGS_MASK, expires);

        return tokenId;
    }

    /**
     * @dev Import multiple migrated names in a batch
     * @param labels Array of labels
     * @param owners Array of owners
     * @param registries Array of registries
     * @param flagsArray Array of flags
     * @param expiresArray Array of expiration timestamps
     */
    function batchImportMigratedNames(
        string[] calldata labels,
        address[] calldata owners,
        IRegistry[] calldata registries,
        uint96[] calldata flagsArray,
        uint64[] calldata expiresArray
    ) external onlyRole(MIGRATION_CONTROLLER_ROLE) {
        require(
            labels.length == owners.length && labels.length == registries.length && labels.length == flagsArray.length
                && labels.length == expiresArray.length,
            "Array lengths must match"
        );

        for (uint256 i = 0; i < labels.length; i++) {
            importMigratedName(labels[i], owners[i], registries[i], flagsArray[i], expiresArray[i]);
        }

        emit BatchMigrationCompleted(labels.length);
    }

    // =================== Interface Support ===================

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable, BaseRegistry)
        returns (bool)
    {
        return interfaceId == type(IRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    // =================== Helper Methods ===================

    /**
     * @dev Extract expiry from flags
     */
    function _extractExpiry(uint96 flags) private pure returns (uint64) {
        return uint64(flags >> 32);
    }
}
