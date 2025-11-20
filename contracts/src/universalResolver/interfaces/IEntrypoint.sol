// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistry} from "../../common/registry/interfaces/IRegistry.sol";

interface IEntrypoint {
    error NameNotIncluded(bytes name, bytes baseName);

    /// @notice Find all registries in the ancestry of `name`.
    /// * `findRegistries("") = [<root>]`
    /// * `findRegistries("eth") = [<eth>, <root>]`
    /// * `findRegistries("nick.eth") = [<nick>, <eth>, <root>]`
    /// * `findRegistries("sub.nick.eth") = [null, <nick>, <eth>, <root>]`
    ///
    /// @param name The DNS-encoded name.
    ///
    /// @return Array of registries in label-order.
    function findRegistries(bytes calldata name) external view returns (IRegistry[] memory);
}
