// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface NameErrors {
    error LabelIsEmpty();
    error LabelIsTooLong(string label);

    /// @dev The DNS-encoded name is malformed.
    ///      Error selector: `0xba4adc23`
    error DNSDecodingFailed(bytes dns);

    /// @dev A label of the ENS name has an invalid size.
    ///      Error selector: `0x9a4c3e3b`
    error DNSEncodingFailed(string ens);

    /// @dev The `name` did not end with `suffix`.
    ///
    /// @param name The DNS-encoded name.
    /// @param suffix THe DNS-encoded suffix.
    error NoSuffixMatch(bytes name, bytes suffix);
}
