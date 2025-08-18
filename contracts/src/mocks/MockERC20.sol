// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory symbol, uint8 decimals_) ERC20(symbol, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function nuke(address owner) external {
        _burn(owner, balanceOf(owner));
    }
}

contract MockERC20Blacklist is MockERC20 {
    error Blacklisted(address);
    mapping(address => bool) public isBlacklisted;
    constructor() MockERC20("USDC", 6) {}
    function setBlacklisted(address account, bool blacklisted) external {
        isBlacklisted[account] = blacklisted;
    }
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        if (isBlacklisted[from]) revert Blacklisted(from);
        if (isBlacklisted[to]) revert Blacklisted(to);
        return super.transferFrom(from, to, amount);
    }
}

contract MockERC20VoidReturn is MockERC20 {
    constructor() MockERC20("USDT", 6) {}
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        super.transferFrom(from, to, amount);
        assembly {
            return(0, 0) // return void
        }
    }
}

contract MockERC20FalseReturn is MockERC20 {
    bool public shouldFail;
    constructor() MockERC20("FALSE", 18) {}
    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        return false; // return false instead of revert
    }
}
