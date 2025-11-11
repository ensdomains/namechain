// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";

import {IAddressResolver} from "@ens/contracts/resolvers/profiles/IAddressResolver.sol";
import {ITextResolver} from "@ens/contracts/resolvers/profiles/ITextResolver.sol";

import {
    ResolverProfileDecoderLib
} from "~src/common/resolver/libraries/ResolverProfileDecoderLib.sol";

contract ResolverProfileDecoderLibTest is Test {
    function testFuzz_isText(string memory key) external pure {
        assertTrue(
            ResolverProfileDecoderLib.isText(
                abi.encodeCall(ITextResolver.text, (~keccak256(bytes(key)), key)),
                keccak256(bytes(key))
            )
        );
    }

    function testFuzz_isText_junk(bytes memory v) external pure {
        assertFalse(ResolverProfileDecoderLib.isText(v, keccak256(v)));
    }

    function testFuzz_isAddr(uint256 coinType) external pure {
        assertTrue(
            ResolverProfileDecoderLib.isAddr(
                abi.encodeCall(
                    IAddressResolver.addr,
                    (~keccak256(abi.encodePacked(coinType)), coinType)
                ),
                coinType
            )
        );
    }

    function testFuzz_isAddr_junk(bytes memory v) external pure {
        assertFalse(ResolverProfileDecoderLib.isAddr(v, uint256(keccak256(v))));
    }
}
