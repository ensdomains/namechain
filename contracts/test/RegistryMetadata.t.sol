// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";
import {UserRegistry} from "../src/registry/UserRegistry.sol";
import {ETHRegistry} from "../src/registry/ETHRegistry.sol";
import {IRegistry} from "../src/registry/IRegistry.sol";
import {RegistryDatastore} from "../src/registry/RegistryDatastore.sol";
import {IRegistryMetadata} from "../src/registry/IRegistryMetadata.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract RegistryMetadataTest is Test, ERC1155Holder {
    RegistryDatastore datastore;
    UserRegistry registry;
    ETHRegistry parentRegistry;
    MockRegistryMetadata metadata;

    function setUp() public {
        datastore = new RegistryDatastore();
        
        parentRegistry = new ETHRegistry(datastore);
        parentRegistry.grantRole(parentRegistry.REGISTRAR_ROLE(), address(this));

        metadata = new MockRegistryMetadata();
        
        registry = new UserRegistry(
            parentRegistry,
            "test",
            datastore,
            metadata
        );

        parentRegistry.register("test", address(this), registry, 0, uint64(block.timestamp + 1000));
    }

    function test_registry_metadata_token_uri() public {
        string memory expectedUri = "ipfs://test";
        uint256 tokenId = uint256(keccak256(bytes("sub")));

        registry.mint("sub", address(this), registry, 0);

        assertEq(registry.uri(tokenId), "");
        
        metadata.setTokenUri(tokenId, expectedUri);
        assertEq(metadata.tokenUri(tokenId), expectedUri);
        assertEq(registry.uri(tokenId), expectedUri);
    }
} 

contract MockRegistryMetadata is IRegistryMetadata {
    mapping(uint256 => string) private _tokenUris;

    function setTokenUri(uint256 tokenId, string calldata uri) external {
        _tokenUris[tokenId] = uri;
    }

    function tokenUri(uint256 tokenId) external view returns (string memory) {
        return _tokenUris[tokenId];
    }
} 