// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {UserRegistry} from "../src/registry/UserRegistry.sol";
import {ETHRegistry} from "../src/registry/ETHRegistry.sol";
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
    UserRegistry registry;
    ETHRegistry parentRegistry;
    SimpleRegistryMetadata metadata;

    function setUp() public {
        datastore = new RegistryDatastore();
        metadata = new SimpleRegistryMetadata();
        
        parentRegistry = new ETHRegistry(datastore, metadata);

        uint256 parentTokenId = parentRegistry.register("test", address(this), registry, address(0), 0, 0, uint64(block.timestamp + 1000));
        
        registry = new UserRegistry(
            parentRegistry,
            parentTokenId,
            datastore,
            metadata
        );
    }

    function test_registry_metadata_token_uri() public {
        string memory expectedUri = "ipfs://test";
        uint256 tokenId = NameUtils.labelToTokenId("test");

        registry.mint("test", address(this), registry, 0);

        assertEq(registry.uri(tokenId), "");
        
        metadata.setTokenUri(tokenId, expectedUri);

        assertEq(metadata.tokenUri(tokenId), expectedUri);
        assertEq(registry.uri(tokenId), expectedUri);
    }

    function test_registry_metadata_unauthorized() public {
        uint256 tokenId = NameUtils.labelToTokenId("test");
        string memory expectedUri = "ipfs://test";

        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, metadata.ROOT_RESOURCE(), metadata.ROLE_UPDATE_METADATA(), address(1))); 
        vm.prank(address(1));
        metadata.setTokenUri(tokenId, expectedUri);
    }

    function test_registry_metadata_supports_interface() public view {
        assertEq(metadata.supportsInterface(type(IRegistryMetadata).interfaceId), true);
        assertEq(metadata.supportsInterface(type(IERC165).interfaceId), true);
    }
} 