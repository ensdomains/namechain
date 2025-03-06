// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import {ERC1155SingletonUpgradeable} from "./ERC1155SingletonUpgradable.sol";
import {IERC1155Singleton} from "./IERC1155Singleton.sol";

import {IRegistry} from "./IRegistry.sol";
import {IRegistryDatastore} from "./IRegistryDatastore.sol";

/**
 * @title UserRegistry
 * @dev Default registry for user names that can be deployed using VerifiableFactory.
 * This registry handles creation and management of subnames.
 */
contract UserRegistry is 
    Initializable,
    UUPSUpgradeable, 
    AccessControlUpgradeable, 
    ERC1155SingletonUpgradeable,
    IRegistry // IRegistry extends IERC1155Singleton which has ownerOf
{
    // =================== Constants ===================
    
    uint96 public constant FLAGS_MASK = 0x7;
    uint96 public constant FLAG_SUBREGISTRY_LOCKED = 0x1;
    uint96 public constant FLAG_RESOLVER_LOCKED = 0x2;
    uint96 public constant FLAG_FLAGS_LOCKED = 0x4;
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    // =================== Storage Variables ===================
    
    IRegistryDatastore public datastore;
    IRegistry public parent;
    string public label;
    
    // Storage gap for future upgrades
    uint256[50] private __gap;
    
    // =================== Errors ===================
    
    error AccessDenied(uint256 tokenId, address owner, address caller);
    error InvalidSubregistryFlags(uint256 tokenId, uint96 flags, uint96 expected);
    error InvalidResolverFlags(uint256 tokenId, uint96 flags, uint96 expected);
    
    // =================== Modifiers ===================
    
    modifier onlyTokenOwner(uint256 tokenId) {
        address owner = ownerOf(tokenId);
        if (owner != msg.sender) {
            revert AccessDenied(tokenId, owner, msg.sender);
        }
        _;
    }
    
    modifier onlyNameOwner() {
        uint256 tokenId = (uint256(keccak256(bytes(label))) & ~uint256(FLAGS_MASK));
        address owner = parent.ownerOf(tokenId);
        if (owner != msg.sender) {
            revert AccessDenied(0, owner, msg.sender);
        }
        _;
    }
    
    modifier withSubregistryFlags(uint256 tokenId, uint96 mask, uint96 expected) {
        (, uint96 flags) = datastore.getSubregistry(tokenId);
        if ((flags & mask) != expected) {  // Note the parentheses
            revert InvalidSubregistryFlags(tokenId, flags & mask, expected);
        }
        _;
    }

    modifier withResolverFlags(uint256 tokenId, uint96 mask, uint96 expected) {
        (, uint96 flags) = datastore.getResolver(tokenId);
        if ((flags & mask) != expected) {  // Note the parentheses around flags & mask
            revert InvalidResolverFlags(tokenId, flags & mask, expected);
        }
        _;
    }
    
    // =================== Initialization ===================
    
    /**
     * @dev Initializes the contract.
     */
    function initialize(
        IRegistryDatastore _datastore,
        IRegistry _parent,
        string memory _label,
        address _admin
    ) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        
        datastore = _datastore;
        parent = _parent;
        label = _label;
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }
    
    // =================== IRegistry Implementation ===================
    
    /**
     * @dev See {IRegistry-getSubregistry}.
     */
    function getSubregistry(string calldata sublabel) external view override returns (IRegistry) {
        (address subregistry,) = datastore.getSubregistry(uint256(keccak256(bytes(sublabel))));
        return IRegistry(subregistry);
    }
    
    /**
     * @dev See {IRegistry-getResolver}.
     */
    function getResolver(string calldata sublabel) external view override returns (address resolver) {
        (resolver,) = datastore.getResolver(uint256(keccak256(bytes(sublabel))));
    }
    
    // =================== Subname Management ===================
    
    /**
     * @dev Create a new subname
     * @param sublabel The subname label
     * @param owner The owner of the new subname
     * @param registry The registry to use for the subname
     * @param flags Flags to set on the subname
     * @return tokenId The token ID of the new subname
     */
    function mint(
        string calldata sublabel,
        address owner,
        IRegistry registry,
        uint96 flags
    ) external onlyNameOwner virtual returns (uint256 tokenId) {
        // Calculate the token ID based on the label hash
        tokenId = uint256(keccak256(bytes(sublabel)));
        
        // Apply flags to the lowest bits of the token ID
        tokenId = (tokenId & ~uint256(FLAGS_MASK)) | (flags & FLAGS_MASK);
        
        // Mint the token and set registry
        _mint(owner, tokenId, 1, "");
        datastore.setSubregistry(tokenId, address(registry), flags);
        
        emit NewSubname(sublabel);
        
        return tokenId;
    }
    
    /**
     * @dev Remove a subname from the registry
     * @param tokenId The token ID to burn
     */
    function burn(uint256 tokenId) 
        external 
        onlyTokenOwner(tokenId) 
        withSubregistryFlags(tokenId, FLAG_SUBREGISTRY_LOCKED, 0) 
    {
        address owner = ownerOf(tokenId);
        _burn(owner, tokenId, 1);
        datastore.setSubregistry(tokenId, address(0), 0);
    }
    
    // =================== Registry Control ===================
    
    /**
     * @dev Set the subregistry for a token
     */
    function setSubregistry(uint256 tokenId, IRegistry registry)
        external
        onlyTokenOwner(tokenId)
        withSubregistryFlags(tokenId, FLAG_SUBREGISTRY_LOCKED, 0)
    {
        (, uint96 flags) = datastore.getSubregistry(tokenId);
        datastore.setSubregistry(tokenId, address(registry), flags);
    }
    
    /**
     * @dev Set the resolver for a token
     */
    function setResolver(uint256 tokenId, address resolver)
        external
        onlyTokenOwner(tokenId)
        withSubregistryFlags(tokenId, FLAG_RESOLVER_LOCKED, 0)
    {
        (, uint96 flags) = datastore.getResolver(tokenId);
        datastore.setResolver(tokenId, resolver, flags);
    }
    
    // =================== Flag Operations ===================
    
    /**
     * @dev Set flags for a token
     */
    function setFlags(uint256 tokenId, uint96 newFlags)
        external
        onlyTokenOwner(tokenId)
        withSubregistryFlags(tokenId, FLAG_FLAGS_LOCKED, 0)
        returns (uint96)
    {
        (address subregistry, uint96 oldFlags) = datastore.getSubregistry(tokenId);
        uint96 updatedFlags = oldFlags | (newFlags & FLAGS_MASK);
        datastore.setSubregistry(tokenId, subregistry, updatedFlags);
        return updatedFlags;
    }
    
    /**
     * @dev Lock a subname's subregistry
     */
    function lockSubregistry(uint256 tokenId) 
        external 
        onlyTokenOwner(tokenId) 
    {
        (address subregistry, uint96 flags) = datastore.getSubregistry(tokenId);
        datastore.setSubregistry(tokenId, subregistry, flags | FLAG_SUBREGISTRY_LOCKED);
    }
    
    /**
     * @dev Lock a subname's resolver
     */
    function lockResolver(uint256 tokenId) 
        external 
        onlyTokenOwner(tokenId) 
    {
        (address subregistry, uint96 flags) = datastore.getSubregistry(tokenId);
        datastore.setSubregistry(tokenId, subregistry, flags | FLAG_RESOLVER_LOCKED);
    }
    
    /**
     * @dev Lock a subname's flags
     */
    function lockFlags(uint256 tokenId) 
        external 
        onlyTokenOwner(tokenId) 
    {
        (address subregistry, uint96 flags) = datastore.getSubregistry(tokenId);
        datastore.setSubregistry(tokenId, subregistry, flags | FLAG_FLAGS_LOCKED);
    }
    
    // =================== URI ===================
    
    /**
     * @dev Override uri function
     */
    function uri(uint256) public pure override returns (string memory) {
        return "";
    }


    // =================== Ownership ===================

    /**
     * @dev Explicitly override ownerOf to resolve inheritance conflict
     * between ERC1155SingletonUpgradeable and IRegistry (via IERC1155Singleton)
     */
    function ownerOf(uint256 id) public view override(ERC1155SingletonUpgradeable, IERC1155Singleton) returns (address) {
        return super.ownerOf(id);
    }
    
    // =================== Upgrade Control ===================
    
    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract.
     */
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
    
    // =================== Interface Support ===================
    
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable, ERC1155SingletonUpgradeable, IERC165)
        returns (bool)
    {
        return 
            interfaceId == type(IRegistry).interfaceId || 
            super.supportsInterface(interfaceId);
    }
}
