// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {EnhancedAccessControl} from "../access-control/EnhancedAccessControl.sol";
import {HCAEquivalence} from "../hca/HCAEquivalence.sol";
import {IHCAFactoryBasic} from "../hca/interfaces/IHCAFactoryBasic.sol";

uint256 constant ROLE_SET_NAME = 1 << 0;
uint256 constant ROLE_SET_NAME_ADMIN = ROLE_SET_NAME << 128;

contract AddrRegistrar is EnhancedAccessControl {
    ////////////////////////////////////////////////////////////////////////
    // Types
    ////////////////////////////////////////////////////////////////////////

    struct Entry {
        string name;
        uint256 resource;
    }

    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    /// @notice The maximum number of claimed resources.
    uint256 public getResourceMax;

    mapping(address addr => Entry entry) internal _entries;

    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    event ResourceChanged(address indexed addr, uint256 oldResource, uint256 newResource);
    event NameChanged(address indexed addr, string name, address sender);
    //event NameChanged(address indexed addr, bytes32 indexed node, string name, address sender);

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(IHCAFactoryBasic hcaFactory) HCAEquivalence(hcaFactory) {}

    function reclaim(string calldata name) external {
        address self = _msgSender();
        _register(self, name, self);
    }

    function reclaimWithAdmin(string calldata name, address to) external {
        _register(_msgSender(), name, to);
    }

    function setName(address addr, string calldata name) external {
        Entry storage entry = _entries[addr];
        _checkRoles(entry.resource, ROLE_SET_NAME, _msgSender());
        entry.name = name;
        _emitChange(addr, name);
    }

    function authorize(address addr, address to, bool on) external {
        Entry storage entry = _entries[addr];
        _checkRoles(entry.resource, ROLE_SET_NAME, _msgSender());
        if (on) {
            _grantRoles(entry.resource, ROLE_SET_NAME, to, false);
        } else {
            _revokeRoles(entry.resource, ROLE_SET_NAME, to, false);
        }
    }

    function getName(address addr) external view returns (string memory) {
        return _entries[addr].name;
    }

    function getResource(address addr) external view returns (uint256) {
        return _entries[addr].resource;
    }

    function _register(address addr, string calldata name, address to) internal {
        Entry storage entry = _entries[addr];
        uint256 oldResource = entry.resource;
        uint256 newResource = ++getResourceMax;
        entry.name = name;
        entry.resource = newResource;
        emit ResourceChanged(addr, oldResource, newResource);
        if (bytes(name).length > 0) {
            _emitChange(addr, name);
        }
        _grantRoles(newResource, ROLE_SET_NAME_ADMIN | ROLE_SET_NAME, to, false);
    }

    function _emitChange(address addr, string memory name) internal {
        // bytes32 node = NameCoder.namehash(NameCoder.encode(name), 0);
        // emit NameChanged(addr, node, name, _msgSender());
        emit NameChanged(addr, name, _msgSender());
    }
}
