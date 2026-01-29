// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface IUniversalSignatureValidator {
    function isValidSig(
        address signer,
        bytes32 hash,
        bytes calldata signature
    ) external returns (bool);
}
