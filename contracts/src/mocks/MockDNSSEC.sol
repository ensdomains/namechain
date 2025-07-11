// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {DNSSEC} from "@ens/contracts/dnssec-oracle/DNSSEC.sol";
import {RRUtils} from "@ens/contracts/dnssec-oracle/RRUtils.sol";

/// @dev This DNSSEC impl ignores the gateway response and returns the rrs
///      supplied to `setResponse()` from `verifyRRSet()` and never fails.
contract MockDNSSEC is DNSSEC {
    bytes rrs;

    function setResponse(bytes memory _rrs) external {
        rrs = _rrs;
    }

    function verifyRRSet(
        RRSetWithSignature[] memory input
    ) external view override returns (bytes memory, uint32) {
        return verifyRRSet(input, block.timestamp);
    }

    function verifyRRSet(
        RRSetWithSignature[] memory,
        uint256
    ) public view override returns (bytes memory, uint32) {
        return (rrs, 0);
    }
}
