// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {CCIPReader} from "@ens/contracts/ccipRead/CCIPBatcher.sol";
import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";
import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";

contract MockNestedResolver is ERC165, CCIPReader, IExtendedResolver {
    IUniversalResolver public immutable universalResolver;

    constructor(
        IUniversalResolver _universalResolver
    ) CCIPReader(DEFAULT_UNSAFE_CALL_GAS) {
        universalResolver = _universalResolver;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165) returns (bool) {
        return
            type(IExtendedResolver).interfaceId == interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function resolve(
        bytes memory name,
        bytes calldata data
    ) external view returns (bytes memory) {
        ccipRead(
            address(universalResolver),
            abi.encodeCall(
                IUniversalResolver.resolve,
                (abi.encodePacked("\x06nested", name), data)
            )
        );
    }
}
