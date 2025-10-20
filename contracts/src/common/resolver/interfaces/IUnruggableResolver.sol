// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IGatewayVerifier} from "@unruggable/gateways/contracts/GatewayFetchTarget.sol";

/// @notice A resolver that uses an Unruggable gateway.
/// @dev Interface selector: `0xe4b2bbef`
interface IUnruggableResolver {
    /// @notice Expose Unruggable gateway parameters.
    ///
    /// @return coinType The source rollup coin type.
    /// @return verifier The Unruggable Verifier contract.
    /// @return gatewayURLs The gateways used by `verifier`.
    function unruggableGateway()
        external
        view
        returns (uint256 coinType, IGatewayVerifier verifier, string[] memory gatewayURLs);
}
