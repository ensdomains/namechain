// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title MockL2Registry
 * @dev Mock implementation of L2 ENS Registry for testing cross-chain communication
 */
interface IMockL2Registry {
    function register(
        string calldata name,
        address owner,
        address subregistry,
        address resolver,
        uint96 flags,
        uint64 expires
    ) external returns (uint256 tokenId);
    
    function setOwner(uint256 tokenId, address newOwner) external;
}

contract MockL2Registry is IMockL2Registry {
    event NameRegistered(string name, address owner, address subregistry);
    event OwnerChanged(uint256 tokenId, address newOwner);
    
    mapping(uint256 => address) public owners;
    mapping(uint256 => address) public subregistries;
    mapping(uint256 => address) public resolvers;
    mapping(uint256 => uint96) public flags;
    mapping(uint256 => uint64) public expirations;
    
    /**
     * @dev Register a new name
     * @param name The name to register
     * @param owner The owner of the name
     * @param subregistry The subregistry to use
     * @param resolver The resolver to use
     * @param flags_ The flags to set
     * @param expires The expiration timestamp
     * @return tokenId The token ID of the registered name
     */
    function register(
        string calldata name,
        address owner,
        address subregistry,
        address resolver,
        uint96 flags_,
        uint64 expires
    ) external override returns (uint256 tokenId) {
        tokenId = uint256(keccak256(abi.encodePacked(name)));
        owners[tokenId] = owner;
        subregistries[tokenId] = subregistry;
        resolvers[tokenId] = resolver;
        flags[tokenId] = flags_;
        expirations[tokenId] = expires;
        
        emit NameRegistered(name, owner, subregistry);
        return tokenId;
    }
    
    /**
     * @dev Set the owner of a name
     * @param tokenId The token ID
     * @param newOwner The new owner
     */
    function setOwner(uint256 tokenId, address newOwner) external override {
        // In a real implementation, we'd check that the sender is authorized
        owners[tokenId] = newOwner;
        emit OwnerChanged(tokenId, newOwner);
    }
    
    /**
     * @dev Get the owner of a name
     * @param tokenId The token ID
     * @return The owner address
     */
    function ownerOf(uint256 tokenId) external view returns (address) {
        return owners[tokenId];
    }
    
    /**
     * @dev Check if a name has expired
     * @param tokenId The token ID
     * @return Whether the name has expired
     */
    function isExpired(uint256 tokenId) external view returns (bool) {
        return expirations[tokenId] < block.timestamp;
    }
}
