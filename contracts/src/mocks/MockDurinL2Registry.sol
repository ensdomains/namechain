// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {AddrResolver} from "@ens/contracts/resolvers/profiles/AddrResolver.sol";
import {TextResolver} from "@ens/contracts/resolvers/profiles/TextResolver.sol";
import {InterfaceResolver} from "@ens/contracts/resolvers/profiles/InterfaceResolver.sol";

/// @title Mock Durin l2 Registry
/// @notice Manages ENS subname registration and management on L2
/// @dev Combined Registry, BaseRegistrar from the official .eth contracts
contract MockDurinL2Registry is AddrResolver, TextResolver, InterfaceResolver {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error LabelTooShort();
    error LabelTooLong(string label);
    error NotAvailable(string label, bytes32 parentNode);


    // bytes32 public baseNode;
    mapping(bytes32 node => bytes name) public names;
    // event ResolverUpdate(address indexed registry, uint256 indexed tokenId, address resolver, uint64 ttl, uint64 gracePeriod);
    event ResolverUpdate(uint256 indexed id, address resolver, uint64 expiry, uint32 data);
    event NewSubname(uint256 indexed _tokenId, string label);
    // constructor(bytes32 _node){
    //     baseNode = _node;
    // }
    function createSubnode(
        bytes32 node,
        string calldata label,
        address _owner,
        bytes[] calldata data
    ) public returns (uint256) {
        bytes32 labelhash = keccak256(bytes(label));
        uint256 tokenId = uint256(labelhash);
        bytes32 subnode = makeNode(node, label);
        bytes memory dnsEncodedName = abi.encodePacked(uint8(bytes(label).length), label, names[node]);
        names[subnode] = dnsEncodedName;
        emit ResolverUpdate(tokenId, address(this), 0, 0);
        emit NewSubname(tokenId, label);
        return tokenId;
    }

    /// @notice Helper to derive a node from a parent node and label
    /// @param parentNode The namehash of the parent, e.g. `namehash("name.eth")` for "name.eth"
    /// @param label The label of the subnode, e.g. "x" for "x.name.eth"
    /// @return The resulting subnode, e.g. `namehash("x.name.eth")` for "x.name.eth"
    function makeNode(
        bytes32 parentNode,
        string calldata label
    ) public pure returns (bytes32) {
        bytes32 labelhash = keccak256(bytes(label));
        return keccak256(abi.encodePacked(parentNode, labelhash));
    }
        
    function isAuthorised(bytes32 node) internal view override returns (bool) {
        return true; // Mock implementation - allow all operations
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _addLabel(
        string memory label,
        bytes memory _name
    ) private pure returns (bytes memory ret) {
        if (bytes(label).length < 1) {
            revert LabelTooShort();
        }
        if (bytes(label).length > 255) {
            revert LabelTooLong(label);
        }
        return abi.encodePacked(uint8(bytes(label).length), label, _name);
    }


    function supportsInterface(
        bytes4 interfaceID
    )
        public
        view
        virtual
        override(
            AddrResolver,
            TextResolver,
            InterfaceResolver
        )
        returns (bool)
    {
        return super.supportsInterface(interfaceID);
    }
}