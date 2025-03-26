// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {UserRegistry} from "../src/L2/UserRegistry.sol";
import {ETHRegistry} from "../src/L2/ETHRegistry.sol";
import {IRegistry} from "../src/common/IRegistry.sol";
import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {IRegistryMetadata} from "../src/common/IRegistryMetadata.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {BaseUriRegistryMetadata} from "../src/common/BaseUriRegistryMetadata.sol";

contract BaseUriRegistryMetadataTest is Test, ERC1155Holder {
    RegistryDatastore datastore;
    UserRegistry registry;
    ETHRegistry parentRegistry;
    BaseUriRegistryMetadata metadata;

    function setUp() public {
        datastore = new RegistryDatastore();
        metadata = new BaseUriRegistryMetadata();
        
        parentRegistry = new ETHRegistry(datastore, metadata);
        parentRegistry.grantRole(parentRegistry.REGISTRAR_ROLE(), address(this));
        
        registry = new UserRegistry(
            parentRegistry,
            "test",
            datastore,
            metadata
        );

        parentRegistry.register("test", address(this), registry, address(0), 0, uint64(block.timestamp + 1000));
    }

    function test_registry_metadata_base_uri() public {
        string memory expectedUri = "ipfs://base/{id}";
        uint256 tokenId = uint256(keccak256(bytes("sub")));

        registry.mint("sub", address(this), registry, 0);

        assertEq(registry.uri(tokenId), "");
        
        metadata.grantRole(metadata.UPDATE_ROLE(), address(this));
        metadata.setTokenUri(expectedUri);

        assertEq(metadata.tokenUri(tokenId), expectedUri);
        assertEq(registry.uri(tokenId), expectedUri);
    }

    function test_registry_metadata_base_uri_multiple_tokens() public {
        string memory expectedUri = "ipfs://base/{id}";
        uint256 tokenId1 = uint256(keccak256(bytes("sub1")));
        uint256 tokenId2 = uint256(keccak256(bytes("sub2")));

        registry.mint("sub1", address(this), registry, 0);
        registry.mint("sub2", address(this), registry, 0);

        metadata.grantRole(metadata.UPDATE_ROLE(), address(this));
        metadata.setTokenUri(expectedUri);

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
        
        metadata.grantRole(metadata.UPDATE_ROLE(), address(this));

        metadata.setTokenUri(initialUri);
        assertEq(metadata.tokenUri(tokenId), initialUri);

        metadata.setTokenUri(updatedUri);
        assertEq(metadata.tokenUri(tokenId), updatedUri);
    }

    function test_registry_metadata_unauthorized() public {
        string memory expectedUri = "ipfs://test/";

        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), metadata.UPDATE_ROLE()));
        metadata.setTokenUri(expectedUri);
    }

    function test_registry_metadata_supports_interface() public view {
        assertEq(metadata.supportsInterface(type(IRegistryMetadata).interfaceId), true);
        assertEq(metadata.supportsInterface(type(IERC165).interfaceId), true);
    }
} 