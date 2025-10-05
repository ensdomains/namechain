// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

import {NameWrapperFixture} from "./fixtures/NameWrapperFixture.sol";

contract TestNameWrapperFixture is NameWrapperFixture {
    function setUp() external {
        deployNameWrapper();
    }

    function test_registerUnwrapped() external {
        registerUnwrapped("test");
    }

    function test_registerUnwrappedETH2LD() external {
        registerWrappedETH2LD("test", 0);
    }

    function test_registerUnwrappedETH3LD() external {
        (, uint256 parentTokenId) = registerWrappedETH2LD("test", 0);
        createWrappedChild(parentTokenId, "sub", 0);
    }

    function test_registerWrappedDNS2LD() external {
        createWrappedName("ens.domains", 0);
    }

    function test_registerWrappedDNS3LD() external {
        (, uint256 parentTokenId) = createWrappedName("ens.domains", 0);
        createWrappedChild(parentTokenId, "sub", 0);
    }

    ////////////////////////////////////////////////////////////////////////
    // Quirks
    ////////////////////////////////////////////////////////////////////////

    function test_Revert_nameWrapper_wrapRoot() external {
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "readLabel: Index out of bounds"));
        nameWrapper.wrap(hex"00", address(1), address(0));
    }

    function test_Revert_nameWrapper_expiryForETH2LD() external {
        (bytes memory name, uint256 tokenId) = registerWrappedETH2LD("test", 0);
        (bytes32 labelHash, ) = NameCoder.readLabel(name, 0);
        (, , uint64 expiry) = nameWrapper.getData(tokenId);
        assertEq(
            ethRegistrarV1.nameExpires(uint256(labelHash)) + ethRegistrarV1.GRACE_PERIOD(),
            uint256(expiry)
        );
    }

    function test_Revert_ethRegistrarV1_ownerOfUnregistered() external {
        vm.expectRevert();
        ethRegistrarV1.ownerOf(0);
    }
}
