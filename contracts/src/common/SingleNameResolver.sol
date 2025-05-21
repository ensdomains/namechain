// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Multicallable} from "@ens/contracts/resolvers/Multicallable.sol";

/**
 * @title SingleNameResolver
 * @dev A resolver tied to a specific registry/name without node parameters
 */
contract SingleNameResolver is IERC165, Multicallable, OwnableUpgradeable {
    bytes4 constant private ADDR_INTERFACE_ID = 0x3b3b57de;
    bytes4 constant private ADDRESS_INTERFACE_ID = 0xf1cb7e06;
    bytes4 constant private TEXT_INTERFACE_ID = 0x59d1d43c;
    bytes4 constant private CONTENTHASH_INTERFACE_ID = 0xbc1c58d1;
    bytes4 constant private PUBKEY_INTERFACE_ID = 0xc8690233;
    bytes4 constant private ABI_INTERFACE_ID = 0x2203ab56;
    bytes4 constant private INTERFACE_INTERFACE_ID = 0x01ffc9a7;
    bytes4 constant private MULTICALL_INTERFACE_ID = 0x5a05180f;
    uint256 constant private ETH_COIN_TYPE = 60;

    event AddrChanged(bytes32 indexed node, address a);
    event AddressChanged(bytes32 indexed node, uint256 coinType, bytes newAddress);
    event TextChanged(bytes32 indexed node, string indexed indexedKey, string key, string value);
    event ContenthashChanged(bytes32 indexed node, bytes hash);
    event PubkeyChanged(bytes32 indexed node, bytes32 x, bytes32 y);
    event ABIChanged(bytes32 indexed node, uint256 indexed contentType);
    event InterfaceChanged(bytes32 indexed node, bytes4 indexed interfaceID, address implementer);
    event NameChanged(bytes32 indexed node, string name);

    // Mapping from coin type to address
    mapping(uint => bytes) private _coinAddresses;

    // Mapping from key to text value
    mapping(string => string) private _textRecords;

    // Content hash
    bytes private _contenthash;

    // Public key
    bytes32 private _pubkeyX;
    bytes32 private _pubkeyY;

    // Mapping from content type to ABI
    mapping(uint256 => bytes) private _abis;

    // Mapping from interface ID to implementer
    mapping(bytes4 => address) private _interfaces;

    /**
     * @dev Initializes the contract with an owner and associated name
     * @param owner The owner of the resolver
     */
    function initialize(address owner) public initializer {
        emit AddrChanged(bytes32(0), owner);
        __Ownable_init(owner);
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
     * @param node The node to get the address for (ignored in SingleNameResolver)
     * @return The address for the associated name
     */
    function addr(bytes32 node) external view returns (address) {
        bytes memory addrBytes = _coinAddresses[ETH_COIN_TYPE];
        if (addrBytes.length == 0) return address(0);
        return bytesToAddress(addrBytes);
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
     * @param node The node to get the address for (ignored in SingleNameResolver)
     * @param coinType The coin type to get the address for
     * @return The address for the specified coin type
     */
    function addr(bytes32 node, uint coinType) external view returns (bytes memory) {
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
     * @param node The node to get the text record for (ignored in SingleNameResolver)
     * @param key The key to get
     * @return The value for the specified key
     */
    function text(bytes32 node, string calldata key) external view returns (string memory) {
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
     * @param node The node to get the content hash for (ignored in SingleNameResolver)
     * @return The content hash for the associated name
     */
    function contenthash(bytes32 node) external view returns (bytes memory) {
        return _contenthash;
    }

    /**
     * @dev Sets the public key for the associated name
     * @param x The x coordinate of the public key
     * @param y The y coordinate of the public key
     */
    function setPubkey(bytes32 x, bytes32 y) external onlyOwner {
        _pubkeyX = x;
        _pubkeyY = y;
        emit PubkeyChanged(bytes32(0), x, y);
    }

    /**
     * @dev Gets the public key for the associated name
     * @param node The node to get the public key for (ignored in SingleNameResolver)
     * @return x The x coordinate of the public key
     * @return y The y coordinate of the public key
     */
    function pubkey(bytes32 node) external view returns (bytes32 x, bytes32 y) {
        return (_pubkeyX, _pubkeyY);
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
     * @param node The node to get the ABI for (ignored in SingleNameResolver)
     * @param contentType The content type of the ABI
     * @return The ABI data
     */
    function ABI(bytes32 node, uint256 contentType) external view returns (uint256, bytes memory) {
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
     * @param node The node to get the implementer for (ignored in SingleNameResolver)
     * @param interfaceID The interface ID
     * @return The implementer address
     */
    function interfaceImplementer(bytes32 node, bytes4 interfaceID) external view returns (address) {
        return _interfaces[interfaceID];
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
        bool supported = interfaceId == ADDR_INTERFACE_ID ||
            interfaceId == ADDRESS_INTERFACE_ID ||
            interfaceId == TEXT_INTERFACE_ID ||
            interfaceId == CONTENTHASH_INTERFACE_ID ||
            interfaceId == PUBKEY_INTERFACE_ID ||
            interfaceId == ABI_INTERFACE_ID ||
            interfaceId == INTERFACE_INTERFACE_ID ||
            interfaceId == MULTICALL_INTERFACE_ID ||
            interfaceId == type(IERC165).interfaceId;
        return supported;
    }
}