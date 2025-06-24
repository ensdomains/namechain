// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {DNSSEC} from "@ens/contracts/dnssec-oracle/DNSSEC.sol";
import {RRUtils} from "@ens/contracts/dnssec-oracle/RRUtils.sol";

contract MockDNSSEC is DNSSEC {
    bytes rrs;
    uint32 inception;

    function setResponse(bytes memory _rrs, uint32 _inception) external {
        rrs = _rrs;
        inception = _inception;
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
        return (rrs, inception);
    }
}
