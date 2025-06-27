// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";
import {DNSTXTScanner} from "../../src/L1/DNSTXTScanner.sol";

contract TestDNSTXTScanner is Test {
    function test_find_whitespace() external pure {
        assertEq(DNSTXTScanner.find("", "a="), "");
        assertEq(DNSTXTScanner.find("  ", "a="), "");
        assertEq(DNSTXTScanner.find("  a=1", "a="), "1");
        assertEq(DNSTXTScanner.find("a=2  ", "a="), "2");
        assertEq(DNSTXTScanner.find(" a=3 ", "a="), "3");
    }

    function test_find_basicKeys() external pure {
        assertEq(DNSTXTScanner.find("a=1", "a="), "1");
        assertEq(DNSTXTScanner.find("bb=2", "bb="), "2");
        assertEq(DNSTXTScanner.find("c[]=3", "c[]="), "3");
    }

    function test_find_keyWithArg() external pure {
        assertEq(DNSTXTScanner.find("a=1 a[b]=1", "a[b]="), "1");
        assertEq(DNSTXTScanner.find("a=1 a[bb]=2", "a[bb]="), "2");
        assertEq(DNSTXTScanner.find("a=a[b] a[b]=3", "a[b]="), "3");
    }

    function test_find_quoted() external pure {
        assertEq(DNSTXTScanner.find("a='b=X' b=1", "b="), "1");
        assertEq(DNSTXTScanner.find("a='a[b]=X' a[b]=2", "a[b]="), "2");
        assertEq(DNSTXTScanner.find("a='\\' a[d]=X' a[d]='3'", "a[d]="), "3");
    }

    function test_find_quotedTouching() external pure {
        assertEq(DNSTXTScanner.find("a='X'b='1'", "b="), "1");
    }
}
