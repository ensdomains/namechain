// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";

contract MockBaseRegistrar is ERC721, IBaseRegistrar {
    mapping(address => bool) public controllers;
    mapping(uint256 => uint256) public expiries;
    uint256 public constant GRACE_PERIOD = 90 days;

    constructor() ERC721("MockETHRegistrar", "METH") {}

    function addController(address controller) external override {
        controllers[controller] = true;
        emit ControllerAdded(controller);
    }

    function removeController(address controller) external override {
        controllers[controller] = false;
        emit ControllerRemoved(controller);
    }

    function setResolver(address) external override {
        // Mock implementation
    }

    function nameExpires(uint256 id) external view override returns (uint256) {
        return expiries[id];
    }

    function available(uint256 id) public view override returns (bool) {
        return expiries[id] + GRACE_PERIOD < block.timestamp || expiries[id] == 0;
    }

    function register(uint256 id, address owner, uint256 duration) external override returns (uint256) {
        require(controllers[msg.sender], "Not a controller");
        require(available(id), "Name not available");
        
        expiries[id] = block.timestamp + duration;
        if (_ownerOf(id) != address(0)) {
            _burn(id);
        }
        _mint(owner, id);
        
        emit NameRegistered(id, owner, block.timestamp + duration);
        return block.timestamp + duration;
    }

    function renew(uint256 id, uint256 duration) external override returns (uint256) {
        require(controllers[msg.sender], "Not a controller");
        require(expiries[id] + GRACE_PERIOD >= block.timestamp, "Name expired");
        
        expiries[id] += duration;
        emit NameRenewed(id, expiries[id]);
        return expiries[id];
    }

    function reclaim(uint256 id, address /*owner*/) external override view {
        require(ownerOf(id) == msg.sender, "Not owner");
        // Mock implementation
    }

    function ownerOf(uint256 tokenId) public view override(ERC721, IERC721) returns (address) {
        require(expiries[tokenId] > block.timestamp, "Name expired");
        return super.ownerOf(tokenId);
    }
}