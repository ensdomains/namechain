import {console} from "forge-std/console.sol";
import {TestV1Mixin} from "./fixtures/TestV1Mixin.sol";

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

contract TestTestV1Mixin is TestV1Mixin {
    function setUp() external {
        deployV1();
    }

    function test_registerUnwrapped() external {
        registerUnwrapped("test");
    }

    ////////////////////////////////////////////////////////////////////////
    // Quirks
    ////////////////////////////////////////////////////////////////////////

    function test_Revert_nameWrapper_wrapRoot() external {
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "readLabel: Index out of bounds"));
        console.log(address(nameWrapper));
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
