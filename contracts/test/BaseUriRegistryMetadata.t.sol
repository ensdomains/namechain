// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {PermissionedRegistry} from "../src/common/PermissionedRegistry.sol";
import {IRegistry} from "../src/common/IRegistry.sol";
import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {BaseUriRegistryMetadata} from "../src/common/BaseUriRegistryMetadata.sol";
import {IRegistryMetadata} from "../src/common/IRegistryMetadata.sol";
import {EnhancedAccessControl} from "../src/common/EnhancedAccessControl.sol";

contract BaseUriRegistryMetadataTest is Test, ERC1155Holder {
    RegistryDatastore datastore;
    PermissionedRegistry registry;
    PermissionedRegistry parentRegistry;
    BaseUriRegistryMetadata metadata;

    uint256 constant ROLE_UPDATE_METADATA = 0x1;
    uint256 constant ROLE_SET_SUBREGISTRY = 0x100;
    uint256 constant ROLE_SET_RESOLVER = 0x1000;
    uint256 constant defaultRoleBitmap = ROLE_SET_SUBREGISTRY | ROLE_SET_RESOLVER;    

    bytes32 constant ROOT_RESOURCE = 0;

    function setUp() public {
        datastore = new RegistryDatastore();
        metadata = new BaseUriRegistryMetadata();
        
        // Use a defined ALL_ROLES value for deployer roles
        uint256 deployerRoles = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        registry = new PermissionedRegistry(
            datastore,
            metadata,
            deployerRoles
        );
    }

    function test_registry_metadata_base_uri() public {
        uint256 tokenId = uint256(keccak256(bytes("sub")));

        registry.register("sub", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp + 1000));

        assertEq(registry.uri(tokenId), "");
        
        string memory expectedUri = "ipfs://base/{id}";
        metadata.setTokenBaseUri(expectedUri);
        assertEq(metadata.tokenUri(tokenId), expectedUri);
        assertEq(registry.uri(tokenId), expectedUri);
    }

    function test_registry_metadata_base_uri_multiple_tokens() public {
        string memory expectedUri = "ipfs://base/{id}";
        uint256 tokenId1 = uint256(keccak256(bytes("sub1")));
        uint256 tokenId2 = uint256(keccak256(bytes("sub2")));

        registry.register("sub1", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp + 1000));
        registry.register("sub2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp + 1000));

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

        registry.register("sub", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp + 1000));
        
        metadata.setTokenBaseUri(initialUri);
        assertEq(metadata.tokenUri(tokenId), initialUri);

        metadata.setTokenBaseUri(updatedUri);
        assertEq(metadata.tokenUri(tokenId), updatedUri);
    }

    function test_registry_metadata_unauthorized() public {
        string memory expectedUri = "ipfs://test/";

        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, ROOT_RESOURCE, ROLE_UPDATE_METADATA, address(1))); 
        vm.prank(address(1));
        metadata.setTokenBaseUri(expectedUri);
    }

    function test_registry_metadata_supports_interface() public view {
        assertEq(metadata.supportsInterface(type(IRegistryMetadata).interfaceId), true);
        assertEq(metadata.supportsInterface(type(EnhancedAccessControl).interfaceId), true);
        assertEq(metadata.supportsInterface(type(IERC165).interfaceId), true);
    }
} 