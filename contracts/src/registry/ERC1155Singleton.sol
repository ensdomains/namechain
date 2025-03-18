// SPDX-License-Identifier: MIT

// ERC1155 implementation that supports only a single token per ID. Stores owner instead of balance to allow
// fetching ownership information for a tokenId via `ownerOf`.
// Portions from OpenZeppelin Contracts (last updated v5.0.0) (token/ERC1155/ERC1155.sol)
pragma solidity >=0.8.13;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {ERC1155SingletonBase} from "./ERC1155SingletonBase.sol";

/**
 * @title ERC1155Singleton
 * @dev Implementation of the ERC1155SingletonBase contract.
 * This provides concrete implementations of the abstract functions defined in the base.
 */
abstract contract ERC1155Singleton is Context, ERC165, ERC1155SingletonBase {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        virtual 
        override(ERC165, ERC1155SingletonBase) 
        returns (bool) 
    {
        return ERC1155SingletonBase.supportsInterface(interfaceId) || ERC165.supportsInterface(interfaceId);
    }

    /**
     * @dev Gets the sender of the current context.
     */
    function _msgSender() internal view virtual override(Context, ERC1155SingletonBase) returns (address) {
        return Context._msgSender();
    }
}
