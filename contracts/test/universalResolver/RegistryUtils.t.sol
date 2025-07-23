// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {RegistryUtils, IRegistry, NameCoder} from "../../src/universalResolver/RegistryUtils.sol";
import {PermissionedRegistry, IRegistryMetadata} from "../../src/common/PermissionedRegistry.sol";
import {RegistryDatastore} from "../../src/common/RegistryDatastore.sol";
import {TestUtils} from "../utils/TestUtils.sol";

contract TestRegistryUtils is Test, ERC1155Holder {
    RegistryDatastore datastore;
    PermissionedRegistry rootRegistry;

    function _createRegistry() internal returns (PermissionedRegistry) {
        return
            new PermissionedRegistry(
                datastore,
                IRegistryMetadata(address(0)),
                TestUtils.ALL_ROLES
            );
    }

    function setUp() public {
        datastore = new RegistryDatastore();
        rootRegistry = _createRegistry();
    }

    function test_readLabel_root() external pure {
        bytes memory name = NameCoder.encode("");
        assertEq(RegistryUtils.readLabel(name, 0), "");
    }
    function test_readLabel_eth() external pure {
        bytes memory name = NameCoder.encode("eth");
        assertEq(RegistryUtils.readLabel(name, 0), "eth");
        assertEq(RegistryUtils.readLabel(name, 4), ""); // 3eth
    }
    function test_readLabel_test_eth() external pure {
        bytes memory name = NameCoder.encode("test.eth");
        assertEq(RegistryUtils.readLabel(name, 0), "test");
        assertEq(RegistryUtils.readLabel(name, 5), "eth"); // 4test
        assertEq(RegistryUtils.readLabel(name, 9), ""); // 4test3eth
    }

    function _readLabel(
        bytes memory name,
        uint256 offset
    ) public pure returns (string memory) {
        return RegistryUtils.readLabel(name, offset);
    }
    function test_Revert_readLabel_invalidOffset() external {
        vm.expectRevert();
        this._readLabel("", 1);
    }
    function test_Revert_readLabel_invalidEncoding() external {
        vm.expectRevert();
        this._readLabel("0x01", 0);
    }
    function test_revert_readLabel_junkAtEnd() external {
        vm.expectRevert();
        this._readLabel("0x0000", 0);
    }

    function _expectRegistries(
        bytes memory name,
        IRegistry[] memory registries
    ) internal view {
        uint256 i;
        for (uint256 offset; i < registries.length; i++) {
            assertEq(
                address(
                    RegistryUtils.findExactRegistry(rootRegistry, name, offset)
                ),
                address(registries[i]),
                "exact"
            );
            (, offset) = NameCoder.readLabel(name, offset);
        }
        assertEq(i, registries.length, "count");
    }

    function test_findResolver_eth() external {
        bytes memory name = NameCoder.encode("eth");
        //     name:  eth
        // registry: <eth> <root>
        // resolver:  0x1
        vm.pauseGasMetering();
        PermissionedRegistry ethRegistry = _createRegistry();
        rootRegistry.register(
            "eth",
            address(this),
            ethRegistry,
            address(1),
            TestUtils.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
        vm.resumeGasMetering();

        (, address resolver, bytes32 node, uint256 offset) = RegistryUtils
            .findResolver(rootRegistry, name, 0);
        assertEq(resolver, address(1), "resolver");
        assertEq(node, NameCoder.namehash(name, 0), "node");
        assertEq(offset, 0, "offset");

        assertEq(
            address(RegistryUtils.findParentRegistry(rootRegistry, name, 0)),
            address(rootRegistry),
            "parentRegistry"
        );

        IRegistry[] memory v = new IRegistry[](2);
        v[0] = ethRegistry;
        v[1] = rootRegistry;
        _expectRegistries(name, v);
    }

    function test_findResolver_resolverOnParent() external {
        bytes memory name = NameCoder.encode("test.eth");
        //     name:  test . eth
        // registry: <test> <eth> <root>
        // resolver:   0x1
        vm.pauseGasMetering();
        PermissionedRegistry ethRegistry = _createRegistry();
        PermissionedRegistry testRegistry = _createRegistry();
        rootRegistry.register(
            "eth",
            address(this),
            ethRegistry,
            address(0),
            TestUtils.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
        ethRegistry.register(
            "test",
            address(this),
            testRegistry,
            address(1),
            TestUtils.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
        vm.resumeGasMetering();

        (, address resolver, bytes32 node, uint256 offset) = RegistryUtils
            .findResolver(rootRegistry, name, 0);
        assertEq(resolver, address(1), "resolver");
        assertEq(node, NameCoder.namehash(name, 0), "node");
        assertEq(offset, 0, "offset");

        assertEq(
            address(RegistryUtils.findParentRegistry(rootRegistry, name, 0)),
            address(ethRegistry),
            "parentRegistry"
        );

        IRegistry[] memory v = new IRegistry[](3);
        v[0] = testRegistry;
        v[1] = ethRegistry;
        v[2] = rootRegistry;
        _expectRegistries(name, v);
    }

    function test_findResolver_resolverOnRoot() external {
        bytes memory name = NameCoder.encode("sub.test.eth");
        //     name:  sub . test . eth
        // registry:       <test> <eth> <root>
        // resolver:               0x1
        vm.pauseGasMetering();
        PermissionedRegistry ethRegistry = _createRegistry();
        PermissionedRegistry testRegistry = _createRegistry();
        rootRegistry.register(
            "eth",
            address(this),
            ethRegistry,
            address(1),
            TestUtils.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
        ethRegistry.register(
            "test",
            address(this),
            testRegistry,
            address(0),
            TestUtils.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
        vm.resumeGasMetering();

        (, address resolver, bytes32 node, uint256 offset) = RegistryUtils
            .findResolver(rootRegistry, name, 0);
        assertEq(resolver, address(1), "resolver");
        assertEq(node, NameCoder.namehash(name, 0), "node");
        assertEq(offset, 9, "offset"); // 3sub4test

        assertEq(
            address(RegistryUtils.findParentRegistry(rootRegistry, name, 0)),
            address(testRegistry),
            "parentRegistry"
        );

        IRegistry[] memory v = new IRegistry[](4);
        v[1] = testRegistry;
        v[2] = ethRegistry;
        v[3] = rootRegistry;
        _expectRegistries(name, v);
    }

    function test_findResolver_virtual() external {
        bytes memory name = NameCoder.encode("a.b.test.eth");
        //     name:  a . b . test . eth
        // registry:         <test> <eth> <root>
        // resolver:                 0x1
        vm.pauseGasMetering();
        PermissionedRegistry ethRegistry = _createRegistry();
        PermissionedRegistry testRegistry = _createRegistry();
        rootRegistry.register(
            "eth",
            address(this),
            ethRegistry,
            address(1),
            TestUtils.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
        ethRegistry.register(
            "test",
            address(this),
            testRegistry,
            address(0),
            TestUtils.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
        vm.resumeGasMetering();

        (, address resolver, bytes32 node, uint256 offset) = RegistryUtils
            .findResolver(rootRegistry, name, 0);
        assertEq(resolver, address(1), "resolver");
        assertEq(node, NameCoder.namehash(name, 0), "node");
        assertEq(offset, 9, "offset"); // 1a1b4test

        assertEq(
            address(RegistryUtils.findParentRegistry(rootRegistry, name, 0)),
            address(0),
            "parentRegistry"
        );

        IRegistry[] memory v = new IRegistry[](5);
        v[2] = testRegistry;
        v[3] = ethRegistry;
        v[4] = rootRegistry;
        _expectRegistries(name, v);
    }
}
