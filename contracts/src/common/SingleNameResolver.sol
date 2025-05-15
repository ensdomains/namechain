// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title SingleNameResolver
 * @dev A resolver tied to a specific registry/name without node parameters
 */
contract SingleNameResolver is OwnableUpgradeable, UUPSUpgradeable, IERC165 {
    // Constants
    uint256 private constant COIN_TYPE_ETH = 60;
    
    // Storage
    mapping(uint256 => bytes) private _addresses;
    mapping(string => string) private _textRecords;
    bytes private _contentHash;
    bytes32 private _associatedName;
    
    // Events
    event AddrChanged(address addr);
    event AddressChanged(uint coinType, bytes newAddress);
    event TextChanged(string indexed key, string value);
    event ContenthashChanged(bytes hash);
    
    /**
     * @dev Initialize the resolver with owner and associated name
     * @param owner_ The owner of this resolver
     * @param associatedName_ The namehash this resolver is associated with
     */
    function initialize(address owner_, bytes32 associatedName_) public initializer {
        __Ownable_init(owner_);
        __UUPSUpgradeable_init();
        _associatedName = associatedName_;
    }
    
    /**
     * @dev Get the namehash this resolver is associated with
     * @return The associated namehash
     */
    function associatedName() external view returns (bytes32) {
        return _associatedName;
    }
    
    /**
     * @dev Set the ETH address
     * @param addr The address to set
     */
    function setAddr(address addr) external onlyOwner {
        bytes memory addrBytes = addressToBytes(addr);
        _addresses[COIN_TYPE_ETH] = addrBytes;
        
        emit AddrChanged(addr);
        emit AddressChanged(COIN_TYPE_ETH, addrBytes);
    }
    
    /**
     * @dev Set the address for a specific coin type
     * @param coinType The coin type to set
     * @param addr The address to set
     */
    function setAddr(uint coinType, bytes calldata addr) external onlyOwner {
        _addresses[coinType] = addr;
        
        emit AddressChanged(coinType, addr);
        if (coinType == COIN_TYPE_ETH && addr.length == 20) {
            emit AddrChanged(bytesToAddress(addr));
        }
    }
    
    /**
     * @dev Get the ETH address
     * @return The ETH address
     */
    function addr() external view returns (address payable) {
        bytes memory addrBytes = _addresses[COIN_TYPE_ETH];
        if (addrBytes.length == 0) {
            return payable(0);
        }
        return bytesToAddress(addrBytes);
    }
    
    /**
     * @dev Get the address for a specific coin type
     * @param coinType The coin type to get
     * @return The address for the specified coin type
     */
    function addr(uint coinType) external view returns (bytes memory) {
        return _addresses[coinType];
    }
    
    /**
     * @dev Set a text record
     * @param key The key to set
     * @param value The value to set
     */
    function setText(string calldata key, string calldata value) external onlyOwner {
        _textRecords[key] = value;
        emit TextChanged(key, value);
    }
    
    /**
     * @dev Get a text record
     * @param key The key to get
     * @return The value for the specified key
     */
    function text(string calldata key) external view returns (string memory) {
        return _textRecords[key];
    }
    
    /**
     * @dev Set the content hash
     * @param hash The content hash to set
     */
    function setContenthash(bytes calldata hash) external onlyOwner {
        _contentHash = hash;
        emit ContenthashChanged(hash);
    }
    
    /**
     * @dev Get the content hash
     * @return The content hash
     */
    function contenthash() external view returns (bytes memory) {
        return _contentHash;
    }
    
    /**
     * @dev Authorize an upgrade to the implementation
     * @param newImplementation The new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    /**
     * @dev Support for various interfaces
     * @param interfaceID The interface ID to check
     * @return Whether the interface is supported
     */
    function supportsInterface(bytes4 interfaceID) public view virtual override returns (bool) {
        return
            interfaceID == type(IERC165).interfaceId ||
            interfaceID == 0x3b3b57de; // IAddrResolver
    }
    
    /**
     * @dev Convert bytes to address
     * @param b The bytes to convert
     * @return The converted address
     */
    function bytesToAddress(bytes memory b) internal pure returns (address payable a) {
        require(b.length == 20);
        assembly {
            a := div(mload(add(b, 32)), exp(256, 12))
        }
    }
    
    /**
     * @dev Convert address to bytes
     * @param a The address to convert
     * @return The converted bytes
     */
    function addressToBytes(address a) internal pure returns (bytes memory b) {
        b = new bytes(20);
        assembly {
            mstore(add(b, 32), mul(a, exp(256, 12)))
        }
    }
}
