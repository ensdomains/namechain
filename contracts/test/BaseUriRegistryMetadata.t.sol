// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {UserRegistry} from "../src/registry/UserRegistry.sol";
import {PermissionedRegistry} from "../src/registry/PermissionedRegistry.sol";
import {IRegistry} from "../src/registry/IRegistry.sol";
import {RegistryDatastore} from "../src/registry/RegistryDatastore.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {BaseUriRegistryMetadata} from "../src/registry/BaseUriRegistryMetadata.sol";
import {RegistryMetadata} from "../src/registry/RegistryMetadata.sol";
import {EnhancedAccessControl} from "../src/registry/EnhancedAccessControl.sol";

contract BaseUriRegistryMetadataTest is Test, ERC1155Holder {
    RegistryDatastore datastore;
    UserRegistry registry;
    PermissionedRegistry parentRegistry;
    BaseUriRegistryMetadata metadata;

    function setUp() public {
        datastore = new RegistryDatastore();
        metadata = new BaseUriRegistryMetadata();
        
        parentRegistry = new PermissionedRegistry(datastore, metadata);

        uint256 parentTokenId = parentRegistry.register("test", address(this), registry, address(0), 0, 0, uint64(block.timestamp + 1000), "");
        
        registry = new UserRegistry(
            parentRegistry,
            parentTokenId,
            datastore,
            metadata
        );
    }

    function test_registry_metadata_base_uri() public {
        string memory expectedUri = "ipfs://base/{id}";
        uint256 tokenId = uint256(keccak256(bytes("sub")));

        registry.mint("sub", address(this), registry, 0);

        assertEq(registry.uri(tokenId), "");
        
        metadata.setTokenBaseUri(expectedUri);

        assertEq(metadata.tokenUri(tokenId), expectedUri);
        assertEq(registry.uri(tokenId), expectedUri);
    }

    function test_registry_metadata_base_uri_multiple_tokens() public {
        string memory expectedUri = "ipfs://base/{id}";
        uint256 tokenId1 = uint256(keccak256(bytes("sub1")));
        uint256 tokenId2 = uint256(keccak256(bytes("sub2")));

        registry.mint("sub1", address(this), registry, 0);
        registry.mint("sub2", address(this), registry, 0);

        metadata.setTokenBaseUri(expectedUri);

        assertEq(metadata.tokenUri(tokenId1), expectedUri);
        assertEq(metadata.tokenUri(tokenId2), expectedUri);
        assertEq(registry.uri(tokenId1), expectedUri);
        assertEq(registry.uri(tokenId2), expectedUri);
    }

    function test_registry_metadata_base_uri_update() public {
        string memory initialUri = "ipfs://initial/{id}";
        string memory updatedUri = "ipfs://updated/{id}";
        uint256 tokenId = uint256(keccak256(bytes("sub")));

        registry.mint("sub", address(this), registry, 0);
        
        metadata.setTokenBaseUri(initialUri);
        assertEq(metadata.tokenUri(tokenId), initialUri);

        metadata.setTokenBaseUri(updatedUri);
        assertEq(metadata.tokenUri(tokenId), updatedUri);
    }

    function test_registry_metadata_unauthorized() public {
        string memory expectedUri = "ipfs://test/";

        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, metadata.ROOT_RESOURCE(), metadata.ROLE_UPDATE_METADATA(), address(1))); 
        vm.prank(address(1));
        metadata.setTokenBaseUri(expectedUri);
    }

    function test_registry_metadata_supports_interface() public view {
        assertEq(metadata.supportsInterface(type(RegistryMetadata).interfaceId), true);
        assertEq(metadata.supportsInterface(type(IERC165).interfaceId), true);
    }
} 