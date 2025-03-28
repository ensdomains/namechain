// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {PermissionedRegistry} from "../src/registry/PermissionedRegistry.sol";
import {IRegistry} from "../src/registry/IRegistry.sol";
import {RegistryDatastore} from "../src/registry/RegistryDatastore.sol";
import {IRegistryMetadata} from "../src/registry/IRegistryMetadata.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SimpleRegistryMetadata} from "../src/registry/SimpleRegistryMetadata.sol";
import {console} from "forge-std/console.sol";
import {NameUtils} from "../src/utils/NameUtils.sol";
import {EnhancedAccessControl} from "../src/registry/EnhancedAccessControl.sol";

contract SimpleRegistryMetadataTest is Test, ERC1155Holder {
    RegistryDatastore datastore;
    PermissionedRegistry registry;
    SimpleRegistryMetadata metadata;

    // Hardcoded role constants
    uint256 constant ROLE_UPDATE_METADATA = 1 << 0;
    bytes32 constant ROOT_RESOURCE = 0;

    // Role bitmaps for different permission configurations
    uint256 constant ROLE_SET_SUBREGISTRY = 1 << 2;
    uint256 constant ROLE_SET_RESOLVER = 1 << 3;
    uint256 constant defaultRoleBitmap = ROLE_SET_SUBREGISTRY | ROLE_SET_RESOLVER;

    function setUp() public {
        datastore = new RegistryDatastore();
        metadata = new SimpleRegistryMetadata();
        registry = new PermissionedRegistry(
            datastore,
            metadata
        );
    }

    function test_registry_metadata_token_uri() public {
        uint256 tokenId = registry.register("test", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp + 1000));

        assertEq(registry.uri(tokenId), "");

        string memory expectedUri = "ipfs://test";
        metadata.setTokenUri(tokenId, expectedUri);
        assertEq(metadata.tokenUri(tokenId), expectedUri);
        assertEq(registry.uri(tokenId), expectedUri);
    }

    function test_registry_metadata_unauthorized() public {
        uint256 tokenId = NameUtils.labelToTokenId("test");
        string memory expectedUri = "ipfs://test";

        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, ROOT_RESOURCE, ROLE_UPDATE_METADATA, address(1))); 
        vm.prank(address(1));
        metadata.setTokenUri(tokenId, expectedUri);
    }

    function test_registry_metadata_supports_interface() public view {
        assertEq(metadata.supportsInterface(type(IRegistryMetadata).interfaceId), true);
        assertEq(metadata.supportsInterface(type(EnhancedAccessControl).interfaceId), true);
        assertEq(metadata.supportsInterface(type(IERC165).interfaceId), true);
    }
} 