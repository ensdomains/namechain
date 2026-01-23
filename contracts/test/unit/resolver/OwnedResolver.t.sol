// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

import {OwnedResolver} from "~src/resolver/OwnedResolver.sol";

contract OwnedResolverTest is Test {
    OwnedResolver resolver;
    bytes testName;

    function setUp() external {
        resolver = new OwnedResolver();
        testName = NameCoder.encode("test.eth");
    }

    function test_alias_noMatch() external view {
        assertEq(resolver.getAlias(testName), "", "test");
        assertEq(resolver.getAlias(NameCoder.encode("")), "", "root");
        assertEq(resolver.getAlias(NameCoder.encode("xyz")), "", "xyz");
    }

    function test_alias_root() external {
        resolver.setAlias(NameCoder.encode(""), testName);

        assertEq(resolver.getAlias(NameCoder.encode("")), testName, "root");
        assertEq(
            resolver.getAlias(NameCoder.encode("sub")),
            NameCoder.addLabel(testName, "sub"),
            "sub"
        );
    }

    function test_alias_wildcardRoot() external {
        resolver.setAlias(NameCoder.encode(""), bytes.concat(hex"00", testName));

        assertEq(resolver.getAlias(NameCoder.encode("")), testName, "exact");
        assertEq(resolver.getAlias(NameCoder.encode("sub")), testName, "sub");
        assertEq(resolver.getAlias(NameCoder.encode("x.y")), testName, "x.y");
    }

    function test_alias_wildcardSubdomain() external {
        resolver.setAlias(NameCoder.encode("a"), bytes.concat(hex"00", testName));

        assertEq(resolver.getAlias(NameCoder.encode("a")), testName, "exact");
        assertEq(resolver.getAlias(NameCoder.encode("")), "", "root");
        assertEq(resolver.getAlias(NameCoder.encode("sub.a")), testName, "sub");
        assertEq(resolver.getAlias(NameCoder.encode("x.y.a")), testName, "x.y");
    }

    function test_alias_exactMatch() external {
        resolver.setAlias(NameCoder.encode("other.eth"), testName);

        assertEq(resolver.getAlias(NameCoder.encode("other.eth")), testName, "exact");
    }

    function test_alias_subdomain() external {
        resolver.setAlias(NameCoder.encode("com"), NameCoder.encode("eth"));

        assertEq(resolver.getAlias(NameCoder.encode("com")), NameCoder.encode("eth"), "exact");
        assertEq(resolver.getAlias(NameCoder.encode("test.com")), testName, "alias");
    }

    function test_alias_recursive() external {
        resolver.setAlias(NameCoder.encode("ens.xyz"), NameCoder.encode("com"));
        resolver.setAlias(NameCoder.encode("com"), NameCoder.encode("eth"));

        assertEq(resolver.getAlias(NameCoder.encode("test.ens.xyz")), testName, "alias");
    }
}
