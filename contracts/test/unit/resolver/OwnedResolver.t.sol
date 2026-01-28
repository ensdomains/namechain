// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

import {OwnedResolver} from "~src/resolver/OwnedResolver.sol";

contract OwnedResolverTest is Test {
    OwnedResolver resolver;

    function setUp() external {
        resolver = new OwnedResolver();
    }

    function test_alias_noMatch() external view {
        assertEq(resolver.getAlias(NameCoder.encode("test.eth")), "", "test");
        assertEq(resolver.getAlias(NameCoder.encode("")), "", "root");
        assertEq(resolver.getAlias(NameCoder.encode("xyz")), "", "xyz");
    }

    function test_alias_root() external {
        resolver.setAlias(NameCoder.encode(""), NameCoder.encode("test.eth"));

        assertEq(resolver.getAlias(NameCoder.encode("")), NameCoder.encode("test.eth"), "root");
        assertEq(
            resolver.getAlias(NameCoder.encode("sub")),
            NameCoder.encode("sub.test.eth"),
            "sub"
        );
    }

    function test_alias_exact() external {
        resolver.setAlias(NameCoder.encode("other.eth"), NameCoder.encode("test.eth"));

        assertEq(
            resolver.getAlias(NameCoder.encode("other.eth")),
            NameCoder.encode("test.eth"),
            "exact"
        );
    }

    function test_alias_subdomain() external {
        resolver.setAlias(NameCoder.encode("com"), NameCoder.encode("eth"));

        assertEq(resolver.getAlias(NameCoder.encode("com")), NameCoder.encode("eth"), "exact");
        assertEq(
            resolver.getAlias(NameCoder.encode("test.com")),
            NameCoder.encode("test.eth"),
            "alias"
        );
    }

    function test_alias_recursive() external {
        resolver.setAlias(NameCoder.encode("ens.xyz"), NameCoder.encode("com"));
        resolver.setAlias(NameCoder.encode("com"), NameCoder.encode("eth"));

        assertEq(
            resolver.getAlias(NameCoder.encode("test.ens.xyz")),
            NameCoder.encode("test.eth"),
            "alias"
        );
    }
}
