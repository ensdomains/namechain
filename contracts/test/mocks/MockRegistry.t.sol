// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {MockRegistry} from "./MockRegistry.sol";
import {IRegistry} from "../../src/common/IRegistry.sol";

contract MockRegistryTest is Test {
    MockRegistry public mockRegistry;
    address public constant TEST_ADDRESS = address(0x123);
    address public constant TEST_SUBREGISTRY = address(0x456);
    address public constant TEST_RESOLVER = address(0x789);
    string public constant TEST_LABEL = "test";

    function setUp() public {
        mockRegistry = new MockRegistry();
    }

    function testSetAndGetSubregistry() public {
        // Set subregistry
        mockRegistry.setSubregistry(TEST_LABEL, TEST_SUBREGISTRY);
        
        // Get subregistry and verify
        IRegistry subregistry = mockRegistry.getSubregistry(TEST_LABEL);
        assertEq(address(subregistry), TEST_SUBREGISTRY);
    }

    function testSetAndGetResolver() public {
        // Set resolver
        mockRegistry.setResolver(TEST_LABEL, TEST_RESOLVER);
        
        // Get resolver and verify
        address resolver = mockRegistry.getResolver(TEST_LABEL);
        assertEq(resolver, TEST_RESOLVER);
    }

    function testBalanceOf() public {
        uint256 balance = mockRegistry.balanceOf(address(0), 0);
        assertEq(balance, 1);
    }

    function testBalanceOfBatch() public {
        address[] memory accounts = new address[](1);
        accounts[0] = address(0);
        
        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;
        
        uint256[] memory balances = mockRegistry.balanceOfBatch(accounts, ids);
        assertEq(balances.length, 1);
        assertEq(balances[0], 1);
    }

    function testSafeTransferFrom() public {
        // This is a no-op function, just verify it doesn't revert
        mockRegistry.safeTransferFrom(address(0), address(0), 0, 0, "");
    }

    function testSafeBatchTransferFrom() public {
        // This is a no-op function, just verify it doesn't revert
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        mockRegistry.safeBatchTransferFrom(address(0), address(0), ids, amounts, "");
    }

    function testSetApprovalForAll() public {
        // This is a no-op function, just verify it doesn't revert
        mockRegistry.setApprovalForAll(address(0), true);
    }

    function testIsApprovedForAll() public {
        bool approved = mockRegistry.isApprovedForAll(address(0), address(0));
        assertTrue(approved);
    }

    function testOwnerOf() public {
        address owner = mockRegistry.ownerOf(0);
        assertEq(owner, TEST_ADDRESS);
    }

    function testSupportsInterface() public {
        bool supported = mockRegistry.supportsInterface(0x12345678);
        assertTrue(supported);
    }
}
