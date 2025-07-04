// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";
import {DNSTXTScanner} from "../../src/L1/dns/DNSTXTScanner.sol";

contract TestDNSTXTScanner is Test {
    function test_find_whitespace() external pure {
        assertEq(DNSTXTScanner.find("", "a="), "");
        assertEq(DNSTXTScanner.find("  ", "a="), "");
        assertEq(DNSTXTScanner.find("a=1  ", "a="), "1");
        assertEq(DNSTXTScanner.find(" a=2 ", "a="), "2");
        assertEq(DNSTXTScanner.find("  a=3", "a="), "3");
    }

    function test_find_ignored() external pure {
        assertEq(DNSTXTScanner.find("a a=1", "a="), "1");
        assertEq(DNSTXTScanner.find("a[b] a=2", "a="), "2");
        assertEq(DNSTXTScanner.find("a[b]junk a=3", "a="), "3");
        assertEq(DNSTXTScanner.find("a[b]' a=4", "a="), "4");
        assertEq(DNSTXTScanner.find("a' a=5", "a="), "5");
        assertEq(DNSTXTScanner.find("' a=6", "a="), "6");
        assertEq(DNSTXTScanner.find("a['] a=7", "a="), "7");
        assertEq(DNSTXTScanner.find("a[''] a=8", "a="), "8");
    }

    function test_find_unquoted() external pure {
        assertEq(DNSTXTScanner.find("a=1", "a="), "1");
        assertEq(DNSTXTScanner.find("bb=2", "bb="), "2");
        assertEq(DNSTXTScanner.find("c[]=3", "c[]="), "3");
    }

    function test_find_unquotedWithArg() external pure {
        assertEq(DNSTXTScanner.find("a=1 a[b]=1", "a[b]="), "1");
        assertEq(DNSTXTScanner.find("a=1 a[bb]=2", "a[bb]="), "2");
        assertEq(DNSTXTScanner.find("a=a[b] a[b]=3", "a[b]="), "3");
    }

    function test_find_quoted() external pure {
        assertEq(DNSTXTScanner.find("a='b=X' b=1", "b="), "1");
        assertEq(DNSTXTScanner.find("a='a[b]=X' a[b]=2", "a[b]="), "2");
        assertEq(DNSTXTScanner.find("a='\\' a[d]=X' a[d]='3'", "a[d]="), "3");
        assertEq(DNSTXTScanner.find("a='\\'\\'\\'\\''", "a="), "''''");
    }

    function test_find_quotedWithoutGap() external pure {
        assertEq(DNSTXTScanner.find("a='X'b='1'", "b="), "1");
    }

    function test_find_quotedWithoutClose() external pure {
        assertEq(DNSTXTScanner.find("a=' a=2", "a="), "");
    }
}
