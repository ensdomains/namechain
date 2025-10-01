// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {INameWrapper, PARENT_CANNOT_CONTROL, CANNOT_UNWRAP, IS_DOT_ETH, CANNOT_TRANSFER, CANNOT_APPROVE} from "@ens/contracts/wrapper/INameWrapper.sol";
import {ERC1155Fuse} from "@ens/contracts/wrapper/ERC1155Fuse.sol";
import {ENS} from "@ens/contracts/registry/ENS.sol";
import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

bytes32 constant ROOT_NODE = 0;
bytes32 constant ETH_NODE = 0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae;

function getUnwrappedTokenId(string memory label) pure returns (uint256) {
    return uint256(keccak256(bytes(label)));
}
function getWrappedTokenId(uint256 id) pure returns (uint256) {
    return uint256(NameCoder.namehash(ETH_NODE, bytes32(id)));
}
function getWrappedTokenId(string memory label) pure returns (uint256) {
    return getUnwrappedTokenId(getWrappedTokenId(label));
}

contract MockNameWrapper is ERC1155Fuse {
    uint64 constant GRACE_PERIOD = 90 days;

    error OperationProhibited(bytes32 node);

    mapping(uint256 => bytes) _names;
    ENS public immutable ens;
    IBaseRegistrar public immutable registrar;

    function uri(uint256 id) external view returns (string memory) {
        return "";
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC1155Fuse) returns (bool) {
        return
            interfaceId == type(INameWrapper).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function names(bytes32 id) external view returns (bytes memory) {
        return _names[uint256(id)];
    }

    function registerAndWrapETH2LD(
        string memory label,
        address owner,
        uint256 duration,
        address resolver,
        uint16 ownerFuses
    ) external returns (uint256 registrarExpiry) {
        registrarExpiry = registrar.register(
            getUnwrappedTokenId(label),
            address(this),
            duration
        );
        wrapETH2LD(label, owner, ownerFuses, resolver);
    }

    function wrapETH2LD(
        string memory label,
        address owner,
        uint16 fuses,
        address resolver
    ) public returns (uint64 expiry) {
        uint256 unwrappedTokenId = getUnwrappedTokenId(label);
        address registrant = registrar.ownerOf(unwrappedTokenId);
        if (registrant != address(this)) {
            registrar.transferFrom(registrant, address(this), unwrappedTokenId);
            registrar.reclaim(unwrappedTokenId, address(this));
        }
        expiry = uint64(registrar.nameExpires(unwrappedTokenId)) + GRACE_PERIOD;
        uint256 id = getWrappedTokenId(label);
        _mint(bytes32(id), owner, fuses, expiry);
        if (resolver != address(0)) {
            ens.setResolver(bytes32(id), resolver);
        }
    }

    function _beforeTransfer(
        uint256 id,
        uint32 fuses,
        uint64 expiry
    ) internal override {
        if (fuses & IS_DOT_ETH != 0) {
            expiry -= GRACE_PERIOD;
        }
        if (expiry < block.timestamp) {
            // Transferable if the name was not emancipated
            if (fuses & PARENT_CANNOT_CONTROL != 0) {
                revert("ERC1155: insufficient balance for transfer");
            }
        } else {
            // Transferable if CANNOT_TRANSFER is unburned
            if (fuses & CANNOT_TRANSFER != 0) {
                revert OperationProhibited(bytes32(id));
            }
        }

        // delete token approval if CANNOT_APPROVE has not been burnt
        if (fuses & CANNOT_APPROVE == 0) {
            delete _tokenApprovals[id];
        }
    }

    function _clearOwnerAndFuses(
        address owner,
        uint32 fuses,
        uint64 expiry
    ) internal override returns (address, uint32) {
        if (expiry < block.timestamp) {
            if (fuses & PARENT_CANNOT_CONTROL != 0) {
                owner = address(0);
            }
            fuses = 0;
        }
        return (owner, fuses);
    }

}

// contract MockNameWrapper is ERC1155Fuse, INameWrapper {
//     uint64 private constant MAX_EXPIRY = type(uint64).max;

//     constructor(
//         ENS _ens,
//         IBaseRegistrar _registrar
//     ) ERC1155Fuse("https://metadata.ens.domains/") {
//         ens = _ens;
//         register = _registrar;

//         _setData(
//             uint256(ETH_NODE),
//             address(0),
//             uint32(PARENT_CANNOT_CONTROL | CANNOT_UNWRAP),
//             MAX_EXPIRY
//         );
//         _setData(
//             uint256(ROOT_NODE),
//             address(0),
//             uint32(PARENT_CANNOT_CONTROL | CANNOT_UNWRAP),
//             MAX_EXPIRY
//         );

//         names[ROOT_NODE] = "\x00";
//         names[ETH_NODE] = "\x03eth\x00";
//     }

//     function registerAndWrapETH2LD(
//         string memory label,
//         address owner,
//         uint256 duration,
//         address resolver,
//         uint16 ownerControlledFuses
//     ) external returns (uint256 registrarExpiry) {
//         registrarExpiry = registrar.register(
//             getUnwrappedTokenId(label),
//             address(this),
//             duration
//         );
//         _wrapETH2LD(
//             label,
//             wrappedOwner,
//             ownerControlledFuses,
//             uint64(registrarExpiry) + GRACE_PERIOD,
//             resolver
//         );
//     }

//     function setResolver(bytes32 node, address resolver) external {
//         resolvers[node] = resolver;
//     }

//     function setFuseData(
//         uint256 tokenId,
//         uint32 _fuses,
//         uint64 _expiry
//     ) external {
//         fuses[tokenId] = _fuses;
//         expiries[tokenId] = _expiry;
//     }

//     function setFuses(
//         bytes32 node,
//         uint16 fusesToBurn
//     ) external returns (uint32) {
//         uint256 tokenId = uint256(node);
//         fuses[tokenId] = fuses[tokenId] | fusesToBurn;
//         return fuses[tokenId];
//     }
// }

// contract MockNameWrapper2 {
//     mapping(uint256 => uint32) public fuses;
//     mapping(uint256 => uint64) public expiries;
//     mapping(uint256 => address) public owners;
//     mapping(uint256 => address) public resolvers;

//     function setFuseData(
//         uint256 tokenId,
//         uint32 _fuses,
//         uint64 _expiry
//     ) external {
//         fuses[tokenId] = _fuses;
//         expiries[tokenId] = _expiry;
//     }

//     function setInitialResolver(uint256 tokenId, address resolver) external {
//         resolvers[tokenId] = resolver;
//     }

//     function getData(
//         uint256 id
//     ) external view returns (address, uint32, uint64) {
//         return (owners[id], fuses[id], expiries[id]);
//     }

//     function setFuses(
//         bytes32 node,
//         uint16 fusesToBurn
//     ) external returns (uint32) {
//         uint256 tokenId = uint256(node);
//         fuses[tokenId] = fuses[tokenId] | fusesToBurn;
//         return fuses[tokenId];
//     }

//     function setResolver(bytes32 node, address resolver) external {
//         uint256 tokenId = uint256(node);
//         resolvers[tokenId] = resolver;
//     }

//     function getResolver(uint256 tokenId) external view returns (address) {
//         return resolvers[tokenId];
//     }
// }

// contract MockNameWrapper1 is ERC1155 {
//     mapping(uint256 => address) private _tokenOwners;
//     mapping(uint256 => uint32) private _tokenFuses;
//     mapping(bytes32 => bytes) public names;

//     constructor() ERC1155("https://metadata.ens.domains/") {}

//     function wrapETH2LD(
//         string memory label,
//         address owner,
//         uint16,
//         address
//     ) external {
//         uint256 tokenId = wrappedTokenId(label);
//         names[bytes32(tokenId)] = NameUtils.dnsEncodeEthLabel(label);
//         _mint(owner, tokenId, 1, "");
//         _tokenOwners[tokenId] = owner;
//     }

//     function ownerOf(uint256 tokenId) external view returns (address) {
//         return _tokenOwners[tokenId];
//     }

//     function getData(
//         uint256 tokenId
//     ) external view returns (address, uint32, uint64) {
//         return (_tokenOwners[tokenId], _tokenFuses[tokenId], 0);
//     }

//     function setFuses(uint256 tokenId, uint32 fuses) external {
//         _tokenFuses[tokenId] = fuses;
//     }

//     function safeTransferFrom(
//         address from,
//         address to,
//         uint256 id,
//         uint256 amount,
//         bytes memory data
//     ) public override {
//         super.safeTransferFrom(from, to, id, amount, data);
//         _tokenOwners[id] = to;
//     }

//     function safeBatchTransferFrom(
//         address from,
//         address to,
//         uint256[] memory ids,
//         uint256[] memory amounts,
//         bytes memory data
//     ) public override {
//         super.safeBatchTransferFrom(from, to, ids, amounts, data);
//         for (uint256 i = 0; i < ids.length; i++) {
//             _tokenOwners[ids[i]] = to;
//         }
//     }

//     function unwrapETH2LD(
//         bytes32 label,
//         address newRegistrant,
//         address /*newController*/
//     ) external {
//         uint256 tokenId = wrappedTokenId(label);
//         // Mock unwrap by burning the ERC1155 token from the caller (migration controller)
//         _burn(msg.sender, tokenId, 1);
//         _tokenOwners[tokenId] = newRegistrant;
//     }
// }
