// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IRegistry} from "../common/IRegistry.sol";
import {IRegistryDatastore} from "../common/IRegistryDatastore.sol";
import {BaseRegistry} from "../common/BaseRegistry.sol";
import {IRegistryMetadata} from "../common/IRegistryMetadata.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {MetadataMixin} from "../common/MetadataMixin.sol";

contract UserRegistry is BaseRegistry, MetadataMixin {
    uint96 public constant SUBREGISTRY_FLAGS_MASK = 0x1;
    uint96 public constant SUBREGISTRY_FLAG_LOCKED = 0x1;

    IRegistry public parent;
    string public label;

    constructor(IRegistry _parent, string memory _label, IRegistryDatastore _datastore, IRegistryMetadata _metadata) BaseRegistry(_datastore) MetadataMixin(_metadata) {
        parent = _parent;
        label = _label;
    }

    modifier onlyNameOwner() {
        address owner = parent.ownerOf(uint256(keccak256(bytes(label))));
        if (owner != msg.sender) {
            revert AccessDenied(0, owner, msg.sender);
        }
        _;
    }

    function mint(string calldata _label, address owner, IRegistry registry, uint96 flags) external onlyNameOwner {
        uint256 tokenId = uint256(keccak256(bytes(_label)));
        _mint(owner, tokenId, 1, "");
        datastore.setSubregistry(tokenId, address(registry), flags);
        emit NewSubname(tokenId, label);
    }

    function burn(uint256 tokenId) external onlyNameOwner withSubregistryFlags(tokenId, SUBREGISTRY_FLAG_LOCKED, 0) {
        address owner = ownerOf(tokenId);
        _burn(owner, tokenId, 1);
        datastore.setSubregistry(tokenId, address(0), 0);
    }

    function locked(uint256 tokenId) external view returns (bool) {
        (, uint96 flags) = datastore.getSubregistry(tokenId);
        return flags & SUBREGISTRY_FLAG_LOCKED != 0;
    }

    function lock(uint256 tokenId) external onlyTokenOwner(tokenId) {
        (address subregistry, uint96 flags) = datastore.getSubregistry(tokenId);
        datastore.setSubregistry(tokenId, subregistry, flags & SUBREGISTRY_FLAG_LOCKED);
    }

    function setSubregistry(uint256 tokenId, IRegistry registry)
        external
        onlyTokenOwner(tokenId)
        withSubregistryFlags(tokenId, SUBREGISTRY_FLAG_LOCKED, 0)
    {
        (, uint96 flags) = datastore.getSubregistry(tokenId);
        datastore.setSubregistry(tokenId, address(registry), flags);
    }

    /**
     * @dev Fetches the token URI for a node.
     * @param tokenId The ID of the node to fetch a URI for.
     * @return The token URI for the node.
     */
    function uri(uint256 tokenId) public view virtual override returns (string memory) {
        return tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IRegistry).interfaceId || super.supportsInterface(interfaceId);
    }
}
