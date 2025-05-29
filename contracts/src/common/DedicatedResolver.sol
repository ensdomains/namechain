// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Multicallable} from "@ens/contracts/resolvers/Multicallable.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

// Resolver profile interfaces
import {IAddrResolver} from "@ens/contracts/resolvers/profiles/IAddrResolver.sol";
import {IAddressResolver} from "@ens/contracts/resolvers/profiles/IAddressResolver.sol";
import {ITextResolver} from "@ens/contracts/resolvers/profiles/ITextResolver.sol";
import {IContentHashResolver} from "@ens/contracts/resolvers/profiles/IContentHashResolver.sol";
import {IPubkeyResolver} from "@ens/contracts/resolvers/profiles/IPubkeyResolver.sol";
import {INameResolver} from "@ens/contracts/resolvers/profiles/INameResolver.sol";
import {IABIResolver} from "@ens/contracts/resolvers/profiles/IABIResolver.sol";
import {IInterfaceResolver} from "@ens/contracts/resolvers/profiles/IInterfaceResolver.sol";
/**
 * @dev Interface for V2 UniversalResolver
 */
interface IUniversalResolverV2 {
    function findResolver(bytes memory name) external view returns (address);
}

/**
 * @title DedicatedResolver
 * @notice A resolver that is dedicated to a single name
 */
contract DedicatedResolver is
    IERC165,
    Multicallable,
    OwnableUpgradeable,
    IInterfaceResolver
{
    // Mapping from coin type to address
    mapping(uint => bytes) private _coinAddresses;

    // Mapping from key to text value
    mapping(string => string) private _textRecords;

    // Content hash
    bytes private _contenthash;

    // Public key
    struct PublicKey {
        bytes32 x;
        bytes32 y;
    }
    PublicKey private _pubkey;

    // Mapping from content type to ABI
    mapping(uint256 => bytes) private _abis;

    // Mapping from interface ID to implementer
    mapping(bytes4 => address) private _interfaces;

    // Name
    string private _name;

    // Wildcard and UniversalResolver
    bool private _wildcard;
    address private _universalResolver;

    uint256 constant private ETH_COIN_TYPE = 60;

    // Events
    event AddrChanged(bytes32 indexed node, address a);
    event AddressChanged(bytes32 indexed node, uint256 coinType, bytes newAddress);
    event TextChanged(bytes32 indexed node, string indexed indexedKey, string key, string value);
    event ContenthashChanged(bytes32 indexed node, bytes hash);
    event PubkeyChanged(bytes32 indexed node, bytes32 x, bytes32 y);
    event ABIChanged(bytes32 indexed node, uint256 indexed contentType);
    event NameChanged(bytes32 indexed node, string name);

    /**
     * @dev Checks if this resolver can return its stored values
     * Returns true if either:
     * 1. Wildcard mode is enabled, or
     * 2. This resolver is the current resolver for the name
     * @param encodedname The encoded name to check
     * @return bool Whether stored values can be returned
     */
    function canReturnStoredValue(bytes memory encodedname) internal view returns (bool) {
        if (!_wildcard) {
            if (_universalResolver == address(0)) {
                // No universal resolver set, so we cannot return stored value
                return false;
            }
            
            address resolver = IUniversalResolverV2(_universalResolver).findResolver(encodedname);
            return resolver == address(this);
        }
        return true;
    }

    /**
     * @dev Initializes the contract with an owner and associated name
     * @param owner The owner of the resolver
     * @param wildcard The wildcard value
     * @param universalResolver The address of the universal resolver
     */
    function initialize(address owner, bool wildcard, address universalResolver) public initializer {
        emit AddrChanged(bytes32(0), owner);
        __Ownable_init(owner);
        _wildcard = wildcard;
        _universalResolver = universalResolver;
    }

    /**
     * @dev Gets the wildcard value
     * @return The wildcard value
     */
    function wildcard() external view returns (bool) {
        return _wildcard;
    }

    /**
     * @dev Gets the universal resolver address
     * @return The universal resolver address
     */
    function universalResolver() external view returns (address) {
        return _universalResolver;
    }

    /**
     * @dev Sets the universal resolver address
     * @param newUniversalResolver The new universal resolver address
     */
    function setUniversalResolver(address newUniversalResolver) external onlyOwner {
        _universalResolver = newUniversalResolver;
        emit UniversalResolverChanged(newUniversalResolver);
    }

    /**
     * @dev Sets the address for the associated name
     * @param addr The address to set
     */
    function setAddr(address addr) external onlyOwner {
        _coinAddresses[ETH_COIN_TYPE] = addressToBytes(addr);
        emit AddrChanged(bytes32(0), addr);
    }

    /**
     * @dev Gets the address for the associated name
     * @param node The node to get the address for (ignored in DedicatedResolver)
     * @return The address for the associated name
     */
    function addr(bytes32 node) private view returns (address payable) {
        bytes memory addrBytes = _coinAddresses[ETH_COIN_TYPE];
        if (addrBytes.length == 0) return payable(address(0));
        return payable(bytesToAddress(addrBytes));
    }

    /**
     * @dev Sets the address for a specific coin type
     * @param coinType The coin type to set the address for
     * @param addr The address to set
     */
    function setAddr(uint coinType, bytes calldata addr) external onlyOwner {
        _coinAddresses[coinType] = addr;
        emit AddressChanged(bytes32(0), coinType, addr);
    }

    /**
     * @dev Gets the address for a specific coin type
     * @param node The node to get the address for (ignored in DedicatedResolver)
     * @param coinType The coin type to get the address for
     * @return The address for the specified coin type
     */
    function addr(bytes32 node, uint coinType) private view returns (bytes memory) {
        return _coinAddresses[coinType];
    }

    /**
     * @dev Sets a text record for the associated name
     * @param key The key to set
     * @param value The value to set
     */
    function setText(string calldata key, string calldata value) external onlyOwner {
        _textRecords[key] = value;
        emit TextChanged(bytes32(0), key, key, value);
    }

    /**
     * @dev Gets a text record for the associated name
     * @param node The node to get the text record for (ignored in DedicatedResolver)
     * @param key The key to get
     * @return The value for the specified key
     */
    function text(bytes32 node, string memory key) private view returns (string memory) {
        return _textRecords[key];
    }

    /**
     * @dev Sets the content hash for the associated name
     * @param hash The content hash to set
     */
    function setContenthash(bytes calldata hash) external onlyOwner {
        _contenthash = hash;
        emit ContenthashChanged(bytes32(0), hash);
    }

    /**
     * @dev Gets the content hash for the associated name
     * @param node The node to get the content hash for (ignored in DedicatedResolver)
     * @return The content hash for the associated name
     */
    function contenthash(bytes32 node) private view returns (bytes memory) {
        return _contenthash;
    }

    /**
     * @dev Sets the public key for the associated name
     * @param x The x coordinate of the public key
     * @param y The y coordinate of the public key
     */
    function setPubkey(bytes32 x, bytes32 y) external onlyOwner {
        _pubkey = PublicKey(x, y);
        emit PubkeyChanged(bytes32(0), x, y);
    }

    /**
     * @dev Gets the public key for the associated name
     * @param node The node to get the public key for (ignored in DedicatedResolver)
     * @return x The x coordinate of the public key
     * @return y The y coordinate of the public key
     */
    function pubkey(bytes32 node) private view returns (bytes32 x, bytes32 y) {
        return (_pubkey.x, _pubkey.y);
    }

    /**
     * @dev Sets the ABI for the associated name
     * @param contentType The content type of the ABI
     * @param data The ABI data
     */
    function setABI(uint256 contentType, bytes calldata data) external onlyOwner {
        _abis[contentType] = data;
        emit ABIChanged(bytes32(0), contentType);
    }

    /**
     * @dev Gets the ABI for the associated name
     * @param node The node to get the ABI for (ignored in DedicatedResolver)
     * @param contentType The content type of the ABI
     * @return The ABI data
     */
    function ABI(bytes32 node, uint256 contentType) private view returns (uint256, bytes memory) {
        return (contentType, _abis[contentType]);
    }

    /**
     * @dev Sets the implementer for an interface
     * @param interfaceID The interface ID
     * @param implementer The implementer address
     */
    function setInterface(bytes4 interfaceID, address implementer) external onlyOwner {
        _interfaces[interfaceID] = implementer;
        emit InterfaceChanged(bytes32(0), interfaceID, implementer);
    }

    /**
     * @dev Gets the implementer for an interface
     * @param node The node to get the implementer for (ignored in DedicatedResolver)
     * @param interfaceID The interface ID
     * @return The implementer address
     */
    function interfaceImplementer(bytes32 node, bytes4 interfaceID) external view returns (address) {
        return _interfaces[interfaceID];
    }

    /**
     * @dev Sets the name for the associated name
     * @param name The name to set
     */
    function setName(string calldata name) external onlyOwner {
        _name = name;
        emit NameChanged(bytes32(0), name);
    }

    /**
     * @dev Gets the name for the associated name
     * @param node The node to get the name for (ignored in DedicatedResolver)
     * @return The name for the associated name
     */
    function name(bytes32 node) private view returns (string memory) {
        return _name;
    }

    /**
     * @dev Converts an address to bytes
     * @param addr The address to convert
     * @return The address as bytes
     */
    function addressToBytes(address addr) internal pure returns (bytes memory) {
        bytes memory b = new bytes(20);
        assembly {
            mstore(add(b, 32), mul(addr, exp(256, 12)))
        }
        return b;
    }

    /**
     * @dev Converts bytes to an address
     * @param b The bytes to convert
     * @return The address
     */
    function bytesToAddress(bytes memory b) internal pure returns (address) {
        require(b.length == 20, "Invalid address length");
        address a;
        assembly {
            a := div(mload(add(b, 32)), exp(256, 12))
        }
        return a;
    }

    /**
     * @dev Checks if the contract supports a specific interface
     * @param interfaceId The interface ID to check
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, Multicallable) returns (bool) {
        return interfaceId == type(IAddrResolver).interfaceId ||
            interfaceId == type(IAddressResolver).interfaceId ||
            interfaceId == type(ITextResolver).interfaceId ||
            interfaceId == type(IContentHashResolver).interfaceId ||
            interfaceId == type(IPubkeyResolver).interfaceId ||
            interfaceId == type(IABIResolver).interfaceId ||
            interfaceId == type(IInterfaceResolver).interfaceId ||
            interfaceId == type(INameResolver).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @dev Emitted when the universal resolver address is changed
     * @param newUniversalResolver The new universal resolver address
     */
    event UniversalResolverChanged(address indexed newUniversalResolver);

    function resolve(bytes calldata encodedname, bytes calldata data) external view returns (bytes memory) {
        bytes32 node = NameCoder.namehash(encodedname, 0);
        if (!canReturnStoredValue(encodedname)) {
            return abi.encode(address(0));
        }

        bytes4 selector = bytes4(data[:4]);
        if (selector == IAddrResolver.addr.selector) {
            return abi.encode(addr(node));
        } else if (selector == IAddressResolver.addr.selector) {
            uint256 coinType = abi.decode(data[4:], (uint256));
            return abi.encode(addr(node, coinType));
        } else if (selector == ITextResolver.text.selector) {
            string memory str = abi.decode(data[4:], (string));
            return abi.encode(text(node, str));
        } else if (selector == IContentHashResolver.contenthash.selector) {
            return abi.encode(contenthash(node));
        } else if (selector == IPubkeyResolver.pubkey.selector) {
            (bytes32 x, bytes32 y) = pubkey(node);
            return abi.encode(x, y);
        } else if (selector == INameResolver.name.selector) {
            return abi.encode(name(node));
        } else if (selector == IABIResolver.ABI.selector) {
            uint256 contentType = abi.decode(data[4:], (uint256));
            (uint256 ct, bytes memory abiData) = ABI(node, contentType);
            return abi.encode(ct, abiData);
        }
        revert("Unsupported resolver function");
    }
}