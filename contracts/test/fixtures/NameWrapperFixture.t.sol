// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {NameWrapperFixture, NameCoder} from "./NameWrapperFixture.sol";

// TODO: add more NameWrapper quirks and invariant tests.
contract TestNameWrapperFixture is NameWrapperFixture {
    function setUp() external {
        _deployNameWrapper();
    }

    ////////////////////////////////////////////////////////////////////////
    // Deployment Helpers
    ////////////////////////////////////////////////////////////////////////

    function test_registerUnwrapped() external {
        (, uint256 tokenId) = registerUnwrapped("test");
        assertEq(ethRegistrarV1.ownerOf(tokenId), user, "owner");
    }

    function test_registerUnwrappedETH2LD() external {
        bytes memory name = registerWrappedETH2LD("test", 0);
        assertEq(nameWrapper.ownerOf(uint256(NameCoder.namehash(name, 0))), user, "owner");
    }

    function test_registerUnwrappedETH3LD() external {
        bytes memory parentName = registerWrappedETH2LD("test", 0);
        bytes memory name = createWrappedChild(parentName, "sub", 0);
        assertEq(nameWrapper.ownerOf(uint256(NameCoder.namehash(name, 0))), user, "owner");
    }

    function test_registerWrappedDNS2LD() external {
        bytes memory name = createWrappedName("ens.domains", 0);
        assertEq(nameWrapper.ownerOf(uint256(NameCoder.namehash(name, 0))), user, "owner");
    }

    function test_registerWrappedDNS3LD() external {
        bytes memory parentName = createWrappedName("ens.domains", 0);
        bytes memory name = createWrappedChild(parentName, "sub", 0);
        assertEq(nameWrapper.ownerOf(uint256(NameCoder.namehash(name, 0))), user, "owner");
    }

    ////////////////////////////////////////////////////////////////////////
    // NameWrapper Quirks
    ////////////////////////////////////////////////////////////////////////

    function test_Revert_nameWrapper_wrapRoot() external {
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "readLabel: Index out of bounds"));
        nameWrapper.wrap(hex"00", address(1), address(0));
    }

    function test_Revert_nameWrapper_expiryForETH2LD() external {
        bytes memory name = registerWrappedETH2LD("test", 0);
        uint256 unwrappedExpiry = ethRegistrarV1.nameExpires(
            uint256(keccak256(bytes(NameCoder.firstLabel(name))))
        );
        (, , uint256 wrappedExpiry) = nameWrapper.getData(uint256(NameCoder.namehash(name, 0)));
        assertEq(unwrappedExpiry + ethRegistrarV1.GRACE_PERIOD(), wrappedExpiry);
    }

    function test_Revert_ethRegistrarV1_ownerOfUnregistered() external {
        vm.expectRevert();
        ethRegistrarV1.ownerOf(0);
    }
}
