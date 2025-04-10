// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title MockL1Registry
 * @dev Mock implementation of L1 ENS Registry for testing cross-chain communication
 */
interface IMockL1Registry {
    function registerEjectedName(
        string calldata name,
        address owner,
        address subregistry,
        uint64 expiry
    ) external returns (uint256 tokenId);
    
    function burnName(uint256 tokenId) external;
}

contract MockL1Registry is IMockL1Registry {
    event NameRegistered(string name, address owner, address subregistry, uint64 expiry);
    event NameBurned(uint256 tokenId);
    
    mapping(uint256 => bool) public registered;
    mapping(uint256 => address) public owners;
    mapping(uint256 => address) public subregistries;
    mapping(uint256 => uint64) public expirations;
    
    /**
     * @dev Register a name that has been ejected from L2 to L1
     * @param name The name to register
     * @param owner The owner of the name
     * @param subregistry The subregistry to use
     * @param expiry The expiration timestamp
     * @return tokenId The token ID of the registered name
     */
    function registerEjectedName(
        string calldata name,
        address owner,
        address subregistry,
        uint64 expiry
    ) external override returns (uint256 tokenId) {
        tokenId = uint256(keccak256(abi.encodePacked(name)));
        registered[tokenId] = true;
        owners[tokenId] = owner;
        subregistries[tokenId] = subregistry;
        expirations[tokenId] = expiry;
        
        emit NameRegistered(name, owner, subregistry, expiry);
        return tokenId;
    }
    
    /**
     * @dev Burn a name, typically when migrating from L1 to L2
     * @param tokenId The token ID to burn
     */
    function burnName(uint256 tokenId) external override {
        registered[tokenId] = false;
        delete owners[tokenId];
        delete subregistries[tokenId];
        delete expirations[tokenId];
        
        emit NameBurned(tokenId);
    }
    
    /**
     * @dev Check if a name is registered
     * @param tokenId The token ID to check
     * @return Whether the name is registered
     */
    function isRegistered(uint256 tokenId) external view returns (bool) {
        return registered[tokenId];
    }
    
    /**
     * @dev Get owner of a name
     * @param tokenId The token ID
     * @return The owner address
     */
    function ownerOf(uint256 tokenId) external view returns (address) {
        return owners[tokenId];
    }
}
