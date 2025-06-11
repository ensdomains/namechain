// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/// @notice Interface for expressing contract features not visible from the ABI.
/// @dev Interface selector: `0xf84e21b5`
interface IFeatureSupporter {
    /// @notice Check if a feature is supported.
    /// @param feature The feature.
    /// @return True if the feature is supported by the contract.
    function supportsFeature(bytes6 feature) external view returns (bool);
}
