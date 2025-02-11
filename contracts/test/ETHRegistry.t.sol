// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "src/registry/ETHRegistry.sol";
import "src/registry/IETHRegistry.sol";
import "src/registry/RegistryDatastore.sol";

contract TestETHRegistry is Test, ERC1155Holder {
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    RegistryDatastore datastore;
    ETHRegistry registry;

    function setUp() public {
        datastore = new RegistryDatastore();
        registry = new ETHRegistry(datastore);
        registry.grantRole(registry.REGISTRAR_ROLE(), address(this));
    }

    function test_register_unlocked() public {
        uint256 expectedId =
            uint256(keccak256("test2") & 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff8);
        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(this), address(0), address(this), expectedId, 1);

        uint256 tokenId = registry.register("test2", address(this), registry, 0, uint64(block.timestamp) + 86400);
        vm.assertEq(tokenId, expectedId);
    }

    function test_register_locked() public {
        uint96 flags = registry.FLAG_SUBREGISTRY_LOCKED() | registry.FLAG_RESOLVER_LOCKED();
        uint256 expectedId =
            uint256(keccak256("test2") & 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff8) | flags;
        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(this), address(0), address(this), expectedId, 1);

        uint256 tokenId = registry.register("test2", address(this), registry, flags, uint64(block.timestamp) + 86400);
        vm.assertEq(tokenId, expectedId);
    }

    function test_lock_name() public {
        uint96 flags = registry.FLAG_SUBREGISTRY_LOCKED() | registry.FLAG_RESOLVER_LOCKED();
        uint256 oldTokenId = registry.register("test2", address(this), registry, 0, uint64(block.timestamp) + 86400);

        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(this), address(this), address(0), oldTokenId, 1);
        uint256 expectedTokenId = oldTokenId | flags;
        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(this), address(0), address(this), expectedTokenId, 1);

        uint256 newTokenId = registry.lock(oldTokenId, flags);
        vm.assertEq(newTokenId, expectedTokenId);
    }

    function test_cannot_unlock_name() public {
        uint96 flags = registry.FLAG_SUBREGISTRY_LOCKED() | registry.FLAG_RESOLVER_LOCKED();

        uint256 oldTokenId = registry.register("test2", address(this), registry, flags, uint64(block.timestamp) + 86400);
        uint256 newTokenId = registry.lock(oldTokenId, 0);
        vm.assertEq(oldTokenId, newTokenId);
    }

    function test_Revert_cannot_mint_duplicates() public {
        uint96 flags = registry.FLAG_SUBREGISTRY_LOCKED() | registry.FLAG_RESOLVER_LOCKED();

        registry.register("test2", address(this), registry, flags, uint64(block.timestamp) + 86400);

        vm.expectRevert(abi.encodeWithSelector(IETHRegistry.NameAlreadyRegistered.selector, "test2"));
        registry.register("test2", address(this), registry, 0, uint64(block.timestamp) + 86400);
    }

    function test_set_subregistry() public {
        uint256 tokenId = registry.register("test2", address(this), registry, 0, uint64(block.timestamp) + 86400);
        registry.setSubregistry(tokenId, IRegistry(address(this)));
        vm.assertEq(address(registry.getSubregistry("test2")), address(this));
    }

    function test_Revert_cannot_set_locked_subregistry() public {
        uint96 flags = registry.FLAG_SUBREGISTRY_LOCKED();
        uint256 tokenId = registry.register("test2", address(this), registry, flags, uint64(block.timestamp) + 86400);

        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.InvalidSubregistryFlags.selector, tokenId, registry.FLAG_SUBREGISTRY_LOCKED(), 0));
        registry.setSubregistry(tokenId, IRegistry(address(this)));
    }

    function test_set_resolver() public {
        uint256 tokenId = registry.register("test2", address(this), registry, 0, uint64(block.timestamp) + 86400);
        registry.setResolver(tokenId, address(this));
        vm.assertEq(address(registry.getResolver("test2")), address(this));
    }

    function test_Revert_cannot_set_locked_resolver() public {
        uint96 flags = registry.FLAG_RESOLVER_LOCKED();
        uint256 tokenId = registry.register("test2", address(this), registry, flags, uint64(block.timestamp) + 86400);

        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.InvalidSubregistryFlags.selector, tokenId, registry.FLAG_RESOLVER_LOCKED(), 0));
        registry.setResolver(tokenId, address(this));
    }

    function test_Revert_cannot_set_locked_flags() public {
        uint96 flags = registry.FLAG_FLAGS_LOCKED();
        uint256 tokenId = registry.register("test2", address(this), registry, flags, uint64(block.timestamp) + 86400);

        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.InvalidSubregistryFlags.selector, tokenId, registry.FLAG_FLAGS_LOCKED(), 0));
        registry.lock(tokenId, flags);
    }

    function test_relinquish() public {
        uint256 tokenId = registry.register("test2", address(this), registry, 0, uint64(block.timestamp) + 86400);
        registry.relinquish(tokenId);
        vm.assertEq(registry.ownerOf(tokenId), address(0));
        vm.assertEq(address(registry.getSubregistry("test2")), address(0));
    }

    function test_Revert_cannot_relinquish_if_not_owner() public {
        uint256 tokenId = registry.register("test2", address(1), registry, 0, uint64(block.timestamp) + 86400);

        vm.prank(address(2));
        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.AccessDenied.selector, tokenId, address(1), address(2)));
        registry.relinquish(tokenId);

        vm.assertEq(registry.ownerOf(tokenId), address(1));
        vm.assertEq(address(registry.getSubregistry("test2")), address(registry));
    }

    function test_expired_name_has_no_owner() public {
        uint256 tokenId = registry.register("test2", address(this), registry, 0, uint64(block.timestamp) + 100);
        vm.warp(block.timestamp + 101);
        assertEq(registry.ownerOf(tokenId), address(0));
    }

    function test_expired_name_can_be_reregistered() public {
        uint256 tokenId = registry.register("test2", address(this), registry, 0, uint64(block.timestamp) + 100);
        vm.warp(block.timestamp + 101);
        
        uint256 newTokenId = registry.register("test2", address(1), registry, 0, uint64(block.timestamp) + 100);
        assertEq(newTokenId, tokenId);
        assertEq(registry.ownerOf(newTokenId), address(1));
    }

    function test_expired_name_returns_zero_subregistry() public {
        registry.register("test2", address(this), registry, 0, uint64(block.timestamp) + 100);
        vm.warp(block.timestamp + 101);
        assertEq(address(registry.getSubregistry("test2")), address(0));
    }

    function test_expired_name_returns_zero_resolver() public {
        uint256 tokenId = registry.register("test2", address(this), registry, 0, uint64(block.timestamp) + 100);
        registry.setResolver(tokenId, address(1));
        vm.warp(block.timestamp + 101);
        assertEq(registry.getResolver("test2"), address(0));
    }

    function test_renew_extends_expiry() public {
        uint256 tokenId = registry.register("test2", address(this), registry, 0, uint64(block.timestamp) + 100);
        uint64 newExpiry = uint64(block.timestamp) + 200;
        registry.renew(tokenId, newExpiry);
        
        (uint64 expiry,) = registry.nameData(tokenId);
        assertEq(expiry, newExpiry);
    }

    function test_Revert_renew_expired_name() public {
        uint256 tokenId = registry.register("test2", address(this), registry, 0, uint64(block.timestamp) + 100);
        vm.warp(block.timestamp + 101);
        
        vm.expectRevert(abi.encodeWithSelector(IETHRegistry.NameExpired.selector, tokenId));
        registry.renew(tokenId, uint64(block.timestamp) + 200);
    }

    function test_Revert_renew_reduce_expiry() public {
        uint256 tokenId = registry.register("test2", address(this), registry, 0, uint64(block.timestamp) + 200);
        uint64 newExpiry = uint64(block.timestamp) + 100;
        
        vm.expectRevert(abi.encodeWithSelector(IETHRegistry.CannotReduceExpiration.selector, uint64(block.timestamp) + 200, newExpiry));
        registry.renew(tokenId, newExpiry);
    }

    function test_Revert_cannot_register_with_past_expiry() public {
        uint64 pastExpiry = uint64(block.timestamp) - 1;
        vm.expectRevert(abi.encodeWithSelector(IETHRegistry.CannotSetPastExpiration.selector, pastExpiry));
        registry.register("test2", address(this), registry, 0, pastExpiry);
    }
}
