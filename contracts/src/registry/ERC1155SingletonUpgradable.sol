// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {IERC1155MetadataURI} from "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";

/**
 * @title IERC1155SingletonUpgradeable
 * @dev Interface for the ERC1155SingletonUpgradeable contract
 */
interface IERC1155SingletonUpgradeable is IERC1155 {
    function ownerOf(uint256 id) external view returns (address owner);
}

/**
 * @title ERC1155SingletonUpgradeable
 * @dev ERC1155 implementation that supports only a single token per ID.
 * Stores owner instead of balance to allow fetching ownership information for a tokenId via `ownerOf`.
 * This is an upgradeable version of the ERC1155Singleton contract.
 */
abstract contract ERC1155SingletonUpgradeable is 
    ERC1155Upgradeable, 
    IERC1155SingletonUpgradeable 
{
    using Arrays for uint256[];
    using Arrays for address[];

    // Event emitted when approval for a specific token is granted
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    // Mapping from token ID to owner address
    mapping(uint256 id => address) private _owners;

    // Storage gap for future upgrades
    uint256[49] private __gap;

    /**
     * @dev See {IERC1155SingletonUpgradeable-ownerOf}.
     */
    function ownerOf(uint256 id) public view virtual override returns (address) {
        return _owners[id];
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        virtual 
        override(ERC1155Upgradeable, IERC165) 
        returns (bool) 
    {
        return 
            interfaceId == type(IERC1155SingletonUpgradeable).interfaceId || 
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC1155-balanceOf}.
     * For a singleton token, the balance is either 0 or 1.
     */
    function balanceOf(address account, uint256 id) 
        public 
        view 
        virtual 
        override(ERC1155Upgradeable, IERC1155) 
        returns (uint256) 
    {
        return ownerOf(id) == account ? 1 : 0;
    }

    /**
     * @dev Internal function to update token owners during transfers
     */
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal virtual override {
        super._update(from, to, ids, values);
        
        // Update ownership tracking
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids.unsafeMemoryAccess(i);
            uint256 value = values.unsafeMemoryAccess(i);
            
            if (value > 0) {
                address owner = _owners[id];
                if (from != address(0) && owner != from) {
                    revert ERC1155InsufficientBalance(from, 0, value, id);
                } else if (value > 1) {
                    revert ERC1155InsufficientBalance(from, 1, value, id);
                }
                _owners[id] = to;
            }
        }
    }
}
