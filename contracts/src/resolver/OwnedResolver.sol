// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

import {OwnedResolverLib} from "./libraries/OwnedResolverLib.sol";

/// @notice An owned resolver that supports multiple names and internal aliasing.
///
/// * Resolved names find the longest match.
/// * Successful matches recursively check for additional aliasing.
/// * Cycles of length 1 apply once.
/// * Cycles of length 2+ result in OOG.
///
/// `setAlias("a.eth", "b.eth")`
/// eg. `getAlias("a.eth") => "b.eth"`
/// eg. `getAlias("[sub].a.eth") => "[sub].b.eth"`
/// eg. `getAlias("[x.y].a.eth") => "[x.y].b.eth"`
/// eg. `getAlias("abc.eth") => ""`
///
contract OwnedResolver {
    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    event AliasChanged(bytes indexed fromName, bytes indexed toName);

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /// @notice Create an alias from `fromName` to `toName`.
    ///
    /// @param fromName The source DNS-encoded name.
    /// @param toName The destination DNS-encoded name.
    function setAlias(bytes calldata fromName, bytes calldata toName) external {
        _storage().aliases[NameCoder.namehash(fromName, 0)] = toName;
        emit AliasChanged(fromName, toName);
    }

    /// @notice Determine which name is queried when `fromName` is resolved.
    ///
    /// @param fromName The source DNS-encoded name.
    ///
    /// @return toName The destination DNS-encoded name or empty if not aliased.
    function getAlias(bytes memory fromName) public view returns (bytes memory toName) {
        bytes32 prev;
        for (;;) {
            bytes memory matchName;
            (matchName, fromName) = _resolveAlias(fromName);
            if (fromName.length == 0) break; // no alias
            bytes32 next = keccak256(matchName);
            if (next == prev) break; // same alias
            toName = fromName;
            prev = next;
        }
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    /// @dev Apply one round of longest match aliasing.
    ///
    /// @param fromName The source DNS-encoded name.
    ///
    /// @return matchName The alias that matched.
    /// @return toName The destination DNS-encoded name or empty if no match.
    function _resolveAlias(
        bytes memory fromName
    ) internal view returns (bytes memory matchName, bytes memory toName) {
        mapping(bytes32 => bytes) storage A = _storage().aliases;
        uint256 offset;
        while (offset < fromName.length) {
            matchName = A[NameCoder.namehash(fromName, offset)];
            if (matchName.length > 0) {
                if (offset > 0) {
                    // rewrite prefix: [x.y].{matchName} => [x.y].{toName}
                    toName = new bytes(offset + matchName.length);
                    assembly {
                        mcopy(add(toName, 32), add(fromName, 32), offset) // copy prefix
                        mcopy(add(toName, add(32, offset)), add(matchName, 32), mload(matchName)) // copy suffix
                    }
                } else {
                    toName = matchName;
                }
                break;
            }
            (, offset) = NameCoder.nextLabel(fromName, offset);
        }
    }

    /// @dev Access global storage pointer.
    function _storage() internal pure returns (OwnedResolverLib.Storage storage S) {
        uint256 slot = OwnedResolverLib.NAMED_SLOT;
        assembly {
            S.slot := slot
        }
    }
}
