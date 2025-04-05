// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/common/MetadataMixin.sol";
import "../src/common/IRegistryMetadata.sol";

// Mock implementation of IRegistryMetadata for testing
contract MockMetadataProvider is IRegistryMetadata {
    mapping(uint256 => string) private _tokenUris;
    
    function setTokenUri(uint256 tokenId, string memory uri) external {
        _tokenUris[tokenId] = uri;
    }
    
    function tokenUri(uint256 tokenId) external view override returns (string memory) {
        return _tokenUris[tokenId];
    }
}

// Concrete implementation of MetadataMixin for testing
contract MetadataMixinImpl is MetadataMixin {
    constructor(IRegistryMetadata _metadataProvider) MetadataMixin(_metadataProvider) {}
    
    // Expose internal function as public for testing
    function updateMetadataProvider(IRegistryMetadata _metadataProvider) public {
        _updateMetadataProvider(_metadataProvider);
    }
    
    // Expose internal function as public for testing
    function getTokenURI(uint256 tokenId) public view returns (string memory) {
        return tokenURI(tokenId);
    }
}

contract MetadataMixinTest is Test {
    MetadataMixinImpl public mixinImpl;
    MockMetadataProvider public mockProvider;
    MockMetadataProvider public newMockProvider;
    
    function setUp() public {
        mockProvider = new MockMetadataProvider();
        mixinImpl = new MetadataMixinImpl(mockProvider);
        newMockProvider = new MockMetadataProvider();
    }
    
    function testInitialMetadataProvider() public view {
        assertEq(address(mixinImpl.metadataProvider()), address(mockProvider));
    }
    
    function testUpdateMetadataProvider() public {
        mixinImpl.updateMetadataProvider(newMockProvider);
        assertEq(address(mixinImpl.metadataProvider()), address(newMockProvider));
    }
    
    function testTokenURI() public {
        // Set token URI in the mock provider
        string memory expectedUri = "ipfs://test-uri";
        uint256 tokenId = 123;
        mockProvider.setTokenUri(tokenId, expectedUri);
        
        // Verify token URI is correctly returned
        string memory uri = mixinImpl.getTokenURI(tokenId);
        assertEq(uri, expectedUri);
    }
    
    function testTokenURIWithZeroAddress() public {
        // Create new implementation with zero address
        MetadataMixinImpl implWithZeroAddr = new MetadataMixinImpl(IRegistryMetadata(address(0)));
        
        // Should return empty string when metadata provider is zero address
        string memory uri = implWithZeroAddr.getTokenURI(123);
        assertEq(uri, "");
    }
    
    function testTokenURIAfterUpdate() public {
        // Set token URI in the new mock provider
        string memory expectedUri = "ipfs://new-test-uri";
        uint256 tokenId = 456;
        newMockProvider.setTokenUri(tokenId, expectedUri);
        
        // Update provider
        mixinImpl.updateMetadataProvider(newMockProvider);
        
        // Verify token URI is correctly returned from new provider
        string memory uri = mixinImpl.getTokenURI(tokenId);
        assertEq(uri, expectedUri);
    }
} 