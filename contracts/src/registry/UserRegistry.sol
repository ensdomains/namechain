// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IRegistry} from "./IRegistry.sol";
import {LockableRegistry} from "./LockableRegistry.sol";
import {NameUtils} from "../utils/NameUtils.sol";

struct SubdomainData {
    IRegistry registry;
    bool locked;
}

contract UserRegistry is LockableRegistry {
    mapping(uint256 => SubdomainData) internal subdomains;
    address internal _resolver;
    IRegistry public parent;

    constructor(
        IRegistry _parent,
        bytes memory name,
        address newResolver
    ) LockableRegistry(name) ERC721("ENS User Registry", "something.eth") {
        parent = _parent;
        if (newResolver != address(0)) {
            _resolver = newResolver;
            emit ResolverChanged(newResolver);
        }
    }

    modifier onlyNameOwner() {
        string memory label = NameUtils.readLabel(canonicalName, 0);
        address owner = parent.ownerOf(uint256(keccak256(bytes(label))));
        if (owner != msg.sender) {
            revert AccessDenied(owner, msg.sender);
        }
        _;
    }

    function setResolver(address newResolver) public onlyNameOwner {
        _resolver = newResolver;
        emit ResolverChanged(_resolver);
    }

    function mint(
        string calldata label,
        address owner,
        IRegistry registry,
        bool locked
    ) external onlyNameOwner {
        uint256 tokenId = uint256(keccak256(bytes(label)));
        _safeMint(owner, tokenId);
        subdomains[tokenId] = SubdomainData(registry, locked);
        emit RegistryChanged(label, registry);
        if (locked) {
            emit SubdomainLocked(label);
        }
    }

    function burn(
        string calldata label
    ) external onlyNameOwner onlyUnlocked(label) {
        uint256 tokenId = uint256(keccak256(bytes(label)));
        _burn(tokenId);
        subdomains[tokenId] = SubdomainData(IRegistry(address(0)), false);
        emit RegistryChanged(label, IRegistry(address(0)));
    }

    function _locked(
        string memory label
    ) internal view override returns (bool) {
        uint256 tokenId = uint256(keccak256(bytes(label)));
        return subdomains[tokenId].locked;
    }

    function _lock(string memory label) internal override {
        uint256 tokenId = uint256(keccak256(bytes(label)));
        subdomains[tokenId].locked = true;
    }

    function setSubregistry(
        string calldata label,
        IRegistry registry
    ) external override onlyTokenOwner(label) onlyUnlocked(label) {
        uint256 tokenId = uint256(keccak256(bytes(label)));
        subdomains[tokenId].registry = registry;
        emit RegistryChanged(label, registry);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(IERC165, ERC721) returns (bool) {
        return
            interfaceId == type(IRegistry).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function getSubregistry(
        string calldata label
    ) external view returns (IRegistry) {
        uint256 tokenId = uint256(keccak256(bytes(label)));
        SubdomainData memory sub = subdomains[tokenId];
        return sub.registry;
    }

    function getResolver() external view returns (address) {
        return _resolver;
    }
}
