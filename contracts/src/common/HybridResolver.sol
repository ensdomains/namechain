// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {AddrResolver} from "@ens/contracts/resolvers/profiles/AddrResolver.sol";
import {ABIResolver} from "@ens/contracts/resolvers/profiles/ABIResolver.sol";
import {ContentHashResolver} from "@ens/contracts/resolvers/profiles/ContentHashResolver.sol";
import {DNSResolver} from "@ens/contracts/resolvers/profiles/DNSResolver.sol";
import {InterfaceResolver} from "@ens/contracts/resolvers/profiles/InterfaceResolver.sol";
import {NameResolver} from "@ens/contracts/resolvers/profiles/NameResolver.sol";
import {PubkeyResolver} from "@ens/contracts/resolvers/profiles/PubkeyResolver.sol";
import {TextResolver} from "@ens/contracts/resolvers/profiles/TextResolver.sol";
import {ExtendedResolver} from "@ens/contracts/resolvers/profiles/ExtendedResolver.sol";
import {Multicallable} from "@ens/contracts/resolvers/Multicallable.sol";
import {NameUtils} from "./NameUtils.sol";

/**
 * @title HybridResolver
 * @dev A resolver that uses label hashes internally for storage efficiency while maintaining
 * name hash compatibility through a mapping layer. This allows for efficient indexing and
 * supports aliasing by allowing multiple name hashes to point to the same label hash.
 */
contract HybridResolver is
    OwnableUpgradeable,
    UUPSUpgradeable,
    ABIResolver,
    AddrResolver,
    ContentHashResolver,
    DNSResolver,
    InterfaceResolver,
    NameResolver,
    PubkeyResolver,
    TextResolver,
    ExtendedResolver,
    Multicallable
{
    // Mapping from namehash to labelHash
    mapping(bytes32 => uint256) private _namehashToLabelHash;
    
    // Mapping from labelHash to namehash (primary namehash for this label)
    mapping(uint256 => bytes32) private _labelHashToPrimaryNamehash;
    
    // Registry this resolver is associated with
    address public registry;

    // Event emitted when a namehash is mapped to a labelHash
    event NamehashMapped(bytes32 indexed namehash, uint256 indexed labelHash, bool isPrimary);

    function initialize(address _owner, address _registry) public initializer {
        __Ownable_init(_owner); // Initialize Ownable
        __UUPSUpgradeable_init();
        registry = _registry;
    }

    /**
     * @dev Maps a namehash to a labelHash. This allows for aliasing where multiple
     * namehashes can point to the same labelHash.
     * @param namehash The namehash to map
     * @param labelHash The labelHash to map to
     * @param isPrimary Whether this namehash should be the primary one for this labelHash
     */
    function mapNamehash(bytes32 namehash, uint256 labelHash, bool isPrimary) external onlyOwner {
        _namehashToLabelHash[namehash] = labelHash;
        
        if (isPrimary) {
            _labelHashToPrimaryNamehash[labelHash] = namehash;
        }
        
        emit NamehashMapped(namehash, labelHash, isPrimary);
    }

    /**
     * @dev Gets the labelHash for a namehash
     * @param namehash The namehash to look up
     * @return The associated labelHash
     */
    function getLabelHash(bytes32 namehash) public view returns (uint256) {
        return _namehashToLabelHash[namehash];
    }

    /**
     * @dev Gets the primary namehash for a labelHash
     * @param labelHash The labelHash to look up
     * @return The primary namehash associated with this labelHash
     */
    function getPrimaryNamehash(uint256 labelHash) public view returns (bytes32) {
        return _labelHashToPrimaryNamehash[labelHash];
    }

    /**
     * @dev Checks if the sender is authorized to modify records
     * @param node The node to check authorization for
     * @return Whether the sender is authorized
     */
    function isAuthorised(bytes32 node) internal view override returns (bool) {
        return msg.sender == owner();
    }

    /**
     * @dev Authorizes an upgrade to the implementation
     * @param newImplementation The new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Overrides the supportsInterface function to report all supported interfaces
     * @param interfaceID The interface identifier to check
     * @return Whether the interface is supported
     */
    function supportsInterface(
        bytes4 interfaceID
    )
        public
        view
        virtual
        override(
            ABIResolver,
            AddrResolver,
            ContentHashResolver,
            DNSResolver,
            InterfaceResolver,
            NameResolver,
            PubkeyResolver,
            TextResolver,
            Multicallable
        )
        returns (bool)
    {
        return super.supportsInterface(interfaceID);
    }

    /**
     * @dev Internal function to get the labelHash for a node, creating a mapping if it doesn't exist
     * @param node The namehash to get the labelHash for
     * @return The labelHash for this node
     */
    function _getOrCreateLabelHash(bytes32 node) internal returns (uint256) {
        uint256 labelHash = getLabelHash(node);
        
        if (labelHash == 0) {
            // If no mapping exists, create one using the canonical form of the namehash
            labelHash = uint256(node);
            _namehashToLabelHash[node] = labelHash;
            
            // If this is the first mapping for this labelHash, set it as primary
            if (_labelHashToPrimaryNamehash[labelHash] == bytes32(0)) {
                _labelHashToPrimaryNamehash[labelHash] = node;
                emit NamehashMapped(node, labelHash, true);
            } else {
                emit NamehashMapped(node, labelHash, false);
            }
        }
        
        return labelHash;
    }

    /**
     * @dev Override for addr(bytes32) to use labelHash internally
     * @param node The namehash to get the address for
     * @return The associated address
     */
    function addr(bytes32 node) public view override returns (address) {
        uint256 labelHash = getLabelHash(node);
        if (labelHash == 0) {
            return address(0);
        }
        
        bytes32 primaryNamehash = _labelHashToPrimaryNamehash[labelHash];
        if (primaryNamehash == bytes32(0)) {
            return address(0);
        }
        
        return super.addr(primaryNamehash);
    }

    /**
     * @dev Override for setAddr(bytes32,address) to use labelHash internally
     * @param node The namehash to set the address for
     * @param a The address to set
     */
    function setAddr(bytes32 node, address a) public override {
        uint256 labelHash = _getOrCreateLabelHash(node);
        bytes32 primaryNamehash = _labelHashToPrimaryNamehash[labelHash];
        
        super.setAddr(primaryNamehash, a);
    }

    // Similar overrides would be implemented for all other resolver methods
    // to use the labelHash internally while maintaining namehash compatibility
}
