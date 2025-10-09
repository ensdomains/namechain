// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test, console} from "forge-std/Test.sol";

import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";

import {WrappedErrorLib} from "~src/common/utils/WrappedErrorLib.sol";

contract MigrationErrorsTest is Test {
    error TypedError(uint256, string);

    function wrapAndRevert(bytes memory v) external pure {
        WrappedErrorLib.wrapAndRevert(v);
    }

    function test_selector() external pure {
        assertEq(
            WrappedErrorLib.ERROR_STRING_SELECTOR,
            bytes4(abi.encodeWithSignature("Error(string)"))
        );
    }

    function test_idempotent_alreadyError() external pure {
        bytes memory err = abi.encodeWithSignature("Error(string)", "abc");
        assertEq(WrappedErrorLib.wrap(err), err, "f(x)");
        assertEq(WrappedErrorLib.wrap(WrappedErrorLib.wrap(err)), err, "f(f(x))");
    }

    function test_idempotent_typedError() external pure {
        bytes memory err = abi.encodeWithSelector(TypedError.selector, 123, "abc");
        assertEq(WrappedErrorLib.wrap(WrappedErrorLib.wrap(err)), WrappedErrorLib.wrap(err));
    }

    function test_wrapAndRevert_alreadyError() external view {
        bytes memory err = abi.encodeWithSignature("Error(string)", "abc");
        try this.wrapAndRevert(err) {} catch (bytes memory v) {
            assertEq(v, err);
        }
    }

    function test_wrapAndRevert_typedError() external view {
        uint256 x = 123;
        string memory y = "abc";
        bytes memory err = abi.encodeWithSelector(TypedError.selector, x, y);
        try this.wrapAndRevert(err) {} catch (bytes memory v) {
            assertEq(WrappedErrorLib.unwrap(v), err);
        }
    }
}
