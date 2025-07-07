// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {CCIPReader} from "@ens/contracts/ccipRead/CCIPBatcher.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {ResolverProfileRewriter} from "../common/ResolverProfileRewriter.sol";
import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";
import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";

/// @dev Test resolver that does not support `resolve(multicall)` and calls an inner UR
///      which, when called from a UR, can test for recursive local batch gateway support.
///      Prepends "nested" subdomain to queried name.
contract MockNestedResolver is ERC165, CCIPReader, IExtendedResolver {
    IUniversalResolver public immutable universalResolver;

    constructor(IUniversalResolver _universalResolver) CCIPReader(0) {
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
        bytes memory subName = abi.encodePacked("\x06nested", name);
        ccipRead(
            address(universalResolver),
            abi.encodeCall(
                IUniversalResolver.resolve,
                (
                    subName,
                    ResolverProfileRewriter.replaceNode(
                        data,
                        NameCoder.namehash(subName, 0)
                    )
                )
            )
        );
    }
}
