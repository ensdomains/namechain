// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title SingleNameResolver
 * @dev A resolver tied to a specific registry/name without node parameters
 */
contract SingleNameResolver is OwnableUpgradeable, IERC165 {
    bytes4 constant private ADDR_INTERFACE_ID = 0x3b3b57de;
    bytes4 constant private ADDRESS_INTERFACE_ID = 0xf1cb7e06;
    bytes4 constant private TEXT_INTERFACE_ID = 0x59d1d43c;
    bytes4 constant private CONTENTHASH_INTERFACE_ID = 0xbc1c58d1;

    event AddrChanged(address addr);
    event AddressChanged(uint coinType, bytes newAddress);
    event TextChanged(string indexed key, string value);
    event ContenthashChanged(bytes hash);

    // Mapping from coin type to address
    mapping(uint => bytes) private _coinAddresses;

    // Mapping from key to text value
    mapping(string => string) private _textRecords;

    // Content hash
    bytes private _contenthash;

    // ETH address (for backward compatibility)
    address payable private _addr;

    /**
     * @dev Initializes the contract with an owner and associated name
     * @param owner The owner of the resolver
     */
    function initialize(address owner) public initializer {
        __Ownable_init(owner);
    }

    /**
     * @dev Sets the address for the associated name
     * @param addr The address to set
     */
    function setAddr(address addr) external onlyOwner {
        _addr = payable(addr);
        emit AddrChanged(addr);
    }

    /**
     * @dev Gets the address for the associated name
     * @return The address for the associated name
     */
    function addr() external view returns (address payable) {
        return _addr;
    }

    /**
     * @dev Sets the address for a specific coin type
     * @param coinType The coin type to set the address for
     * @param addr The address to set
     */
    function setAddr(uint coinType, bytes calldata addr) external onlyOwner {
        _coinAddresses[coinType] = addr;
        emit AddressChanged(coinType, addr);
    }

    /**
     * @dev Gets the address for a specific coin type
     * @param coinType The coin type to get the address for
     * @return The address for the specified coin type
     */
    function addr(uint coinType) external view returns (bytes memory) {
        return _coinAddresses[coinType];
    }

    /**
     * @dev Sets a text record for the associated name
     * @param key The key to set
     * @param value The value to set
     */
    function setText(string calldata key, string calldata value) external onlyOwner {
        _textRecords[key] = value;
        emit TextChanged(key, value);
    }

    /**
     * @dev Gets a text record for the associated name
     * @param key The key to get
     * @return The value for the specified key
     */
    function text(string calldata key) external view returns (string memory) {
        return _textRecords[key];
    }

    /**
     * @dev Sets the content hash for the associated name
     * @param hash The content hash to set
     */
    function setContenthash(bytes calldata hash) external onlyOwner {
        _contenthash = hash;
        emit ContenthashChanged(hash);
    }

    /**
     * @dev Gets the content hash for the associated name
     * @return The content hash for the associated name
     */
    function contenthash() external view returns (bytes memory) {
        return _contenthash;
    }

    /**
     * @dev Checks if the contract supports a specific interface
     * @param interfaceId The interface ID to check
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == ADDR_INTERFACE_ID ||
            interfaceId == ADDRESS_INTERFACE_ID ||
            interfaceId == TEXT_INTERFACE_ID ||
            interfaceId == CONTENTHASH_INTERFACE_ID ||
            interfaceId == type(IERC165).interfaceId;
    }
}