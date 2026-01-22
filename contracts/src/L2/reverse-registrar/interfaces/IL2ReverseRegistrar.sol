// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IL2ReverseRegistrar {
    struct NameClaim {
        string name;
        address addr;
        uint256[] chainIds;
        uint256 expirationTime;
    }

    /// @notice Sets the `nameForAddr()` record for the calling account.
    ///
    /// @param name The name to set.
    function setName(string memory name) external;

    /// @notice Sets the `nameForAddr()` record for the addr provided account.
    ///
    /// @param addr The address to set the name for.
    /// @param name The name to set.
    function setNameForAddr(address addr, string memory name) external;

    /// @notice Sets the `nameForAddr()` record for the addr provided account using a signature.
    ///
    /// @param claim The claim to set the name for.
    /// @param signature The signature from the addr.
    function setNameForAddrWithSignature(
        NameClaim calldata claim,
        bytes calldata signature
    ) external;

    /// @notice Sets the `nameForAddr()` record for the contract provided that is owned with `Ownable`.
    ///
    /// @param claim The claim to set the name for.
    /// @param owner The owner of the contract (via Ownable).
    /// @param signature The signature of an address that will return true on isValidSignature for the owner.
    function setNameForOwnableWithSignature(
        NameClaim calldata claim,
        address owner,
        bytes calldata signature
    ) external;
}
