// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable func-name-mixedcase, namechain/ordering

import {Test} from "forge-std/Test.sol";

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

contract NameCoderTest is Test {
    bytes internal constant _ROOT_NAME = "\x00";
    bytes internal constant _ETH_NAME = "\x03eth\x00";

    ////////////////////////////////////////////////////////////////////////
    // Exposed Library Functions
    ////////////////////////////////////////////////////////////////////////

    function appendLabel(
        bytes calldata name,
        string calldata label
    ) external pure returns (bytes memory) {
        return NameCoder.appendLabel(name, label);
    }

    function ethName(string calldata label) external pure returns (bytes memory) {
        return NameCoder.ethName(label);
    }

    function firstLabel(bytes calldata name) external pure returns (string memory) {
        return NameCoder.firstLabel(name);
    }

    function extractLabel(
        bytes calldata name,
        uint256 offset
    ) external pure returns (string memory label, uint256 nextOffset) {
        return NameCoder.extractLabel(name, offset);
    }

    ////////////////////////////////////////////////////////////////////////
    // ETH_NODE
    ////////////////////////////////////////////////////////////////////////

    function test_ETH_NODE() external pure {
        assertEq(NameCoder.ETH_NODE, NameCoder.namehash(bytes32(0), keccak256("eth")));
    }

    ////////////////////////////////////////////////////////////////////////
    // appendLabel
    ////////////////////////////////////////////////////////////////////////

    function test_appendLabel() external pure {
        bytes memory name = _ROOT_NAME;
        name = NameCoder.appendLabel(name, "eth");
        assertEq(name, _ETH_NAME);
        name = NameCoder.appendLabel(name, "test");
        assertEq(name, "\x04test\x03eth\x00");
        name = NameCoder.appendLabel(name, "sub");
        assertEq(name, "\x03sub\x04test\x03eth\x00");
    }

    function test_Revert_appendLabel_empty() external {
        vm.expectRevert(abi.encodeWithSelector(NameCoder.LabelIsEmpty.selector));
        this.appendLabel(_ROOT_NAME, "");
    }

    function test_appendLabel_min() external pure {
        NameCoder.appendLabel(_ROOT_NAME, new string(1));
    }

    function test_appendLabel_max() external pure {
        NameCoder.appendLabel(_ROOT_NAME, new string(255));
    }

    function test_Revert_appendLabel_tooLong() external {
        string memory label = new string(256);
        vm.expectRevert(abi.encodeWithSelector(NameCoder.LabelIsTooLong.selector, label));
        this.appendLabel(_ROOT_NAME, label);
    }

    ////////////////////////////////////////////////////////////////////////
    // ethName (depends on appendLabel)
    ////////////////////////////////////////////////////////////////////////

    function test_ethName() external pure {
        assertEq(NameCoder.ethName("test"), NameCoder.appendLabel(_ETH_NAME, "test"));
    }

    function testFuzz_ethName(string calldata label) external pure {
        uint256 n = bytes(label).length;
        vm.assume(n > 0 && n < 256);
        assertEq(NameCoder.ethName(label), NameCoder.appendLabel(_ETH_NAME, label));
    }

    function test_ethName_min() external pure {
        assertEq(NameCoder.ethName("a"), NameCoder.appendLabel(_ETH_NAME, "a"));
    }

    function test_ethName_max() external pure {
        string memory label = new string(255);
        assertEq(NameCoder.ethName(label), NameCoder.appendLabel(_ETH_NAME, label));
    }

    function test_Revert_ethName_empty() external {
        vm.expectRevert(abi.encodeWithSelector(NameCoder.LabelIsEmpty.selector));
        this.ethName("");
    }

    function test_Revert_ethName_tooLong() external {
        string memory label = new string(256);
        vm.expectRevert(abi.encodeWithSelector(NameCoder.LabelIsTooLong.selector, label));
        this.ethName(label);
    }

    ////////////////////////////////////////////////////////////////////////
    // firstLabel (depends on ethName)
    ////////////////////////////////////////////////////////////////////////

    function testFuzz_firstLabel(string memory label) external pure {
        uint256 n = bytes(label).length;
        vm.assume(n > 0 && n < 256);
        assertEq(NameCoder.firstLabel(NameCoder.ethName(label)), label);
    }

    function test_firstLabel_stopAllowed() external pure {
        assertEq(NameCoder.firstLabel("\x03a.b\x00"), "a.b");
    }

    function test_Revert_firstLabel_empty() external {
        vm.expectRevert(abi.encodeWithSelector(NameCoder.LabelIsEmpty.selector));
        this.firstLabel(_ROOT_NAME);
    }

    function test_firstLabel_min() external pure {
        string memory label = new string(1);
        assertEq(NameCoder.firstLabel(NameCoder.ethName(label)), label);
    }

    function test_firstLabel_max() external pure {
        string memory label = new string(255);
        assertEq(NameCoder.firstLabel(NameCoder.ethName(label)), label);
    }

    ////////////////////////////////////////////////////////////////////////
    // extractLabel (depends on readLabel)
    ////////////////////////////////////////////////////////////////////////

    // function test_extractLabel_root() external pure {
    //     (string memory label, uint256 offset) = NameCoder.extractLabel(_ROOT_NAME, 0);
    //     assertEq(label, "");
    //     assertEq(offset, 1);
    // }

    // function test_readLabel_eth() external pure {
    //     bytes memory name = NameCoder.encode("eth");
    //     assertEq(LibRegistry.readLabel(name, 0), "eth");
    //     assertEq(LibRegistry.readLabel(name, 4), ""); // 3eth
    // }

    // function test_readLabel_test_eth() external pure {
    //     bytes memory name = NameCoder.encode("test.eth");
    //     assertEq(LibRegistry.readLabel(name, 0), "test");
    //     assertEq(LibRegistry.readLabel(name, 5), "eth"); // 4test
    //     assertEq(LibRegistry.readLabel(name, 9), ""); // 4test3eth
    // }

    // function _readLabel(bytes memory name, uint256 offset) public pure returns (string memory) {
    //     return LibRegistry.readLabel(name, offset);
    // }
    // function test_Revert_readLabel_invalidOffset() external {
    //     vm.expectRevert();
    //     this._readLabel("", 1);
    // }
    // function test_Revert_readLabel_invalidEncoding() external {
    //     vm.expectRevert();
    //     this._readLabel("\x01", 0);
    // }
    // function test_revert_readLabel_junkAtEnd() external {
    //     vm.expectRevert();
    //     this._readLabel("\x001", 0);
    // }
}
