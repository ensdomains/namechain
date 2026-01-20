// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {SignatureUtils} from "@ens/contracts/reverseRegistrar/SignatureUtils.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {
    StandaloneReverseRegistrar
} from "../../common/reverse-registrar/StandaloneReverseRegistrar.sol";
import {LibISO8601} from "../../common/utils/LibISO8601.sol";

import {IL2ReverseRegistrar} from "./interfaces/IL2ReverseRegistrar.sol";

/// @title L2 Reverse Registrar
/// @notice An L2 Reverse Registrar. Deployed to each L2 chain.
contract L2ReverseRegistrar is IL2ReverseRegistrar, ERC165, StandaloneReverseRegistrar {
    using SignatureUtils for bytes;

    using MessageHashUtils for bytes;

    /// @notice The chain id of the chain this contract is deployed to.
    uint256 public immutable CHAIN_ID;

    /// @notice The first 20 characters of the address of the contract.
    bytes32 private immutable _ADDRESS_CHUNK_1;

    /// @notice The second 20 characters of the address of the contract.
    bytes32 private immutable _ADDRESS_CHUNK_2;

    /// @notice The mapping of nonces to used status.
    mapping(bytes32 nonce => bool used) private _nonces;

    /// @notice Thrown when the specified address is not the owner of the contract
    error NotOwnerOfContract();

    error CurrentChainNotFound();

    error NonceAlreadyUsed();

    /// @notice The caller is not authorised to perform the action
    error Unauthorised();

    /// @notice Checks if the caller is authorised
    ///
    /// @param addr The address to check.
    modifier authorised(address addr) {
        if (addr != msg.sender && !_ownsContract(addr, msg.sender)) {
            revert Unauthorised();
        }
        _;
    }

    /// @notice Initialises the contract by setting the coin type.
    ///
    /// @param coinType The coin type of the chain this contract is deployed to.
    /// @param label The hex value of the coin type.
    constructor(uint256 coinType, string memory label) StandaloneReverseRegistrar(coinType, label) {
        CHAIN_ID = (0x7fffffff & coinType) >> 0;
        // this is 40 bytes (20 characters) long
        string memory addressString = Strings.toChecksumHexString(address(this));
        // first 20 characters
        bytes32 chunk1;
        bytes32 chunk2;
        assembly {
            let chunk1ptr := add(addressString, 64)
            let chunk2ptr := add(addressString, 96)
            chunk1 := mload(chunk1ptr)
            chunk2 := mload(chunk2ptr)
        }
        _ADDRESS_CHUNK_1 = chunk1;
        _ADDRESS_CHUNK_2 = chunk2;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceID
    ) public view override(ERC165, StandaloneReverseRegistrar) returns (bool) {
        return
            interfaceID == type(IL2ReverseRegistrar).interfaceId ||
            super.supportsInterface(interfaceID);
    }

    /// @inheritdoc IL2ReverseRegistrar
    function setName(string calldata name) external authorised(msg.sender) {
        _setName(msg.sender, name);
    }

    /// @inheritdoc IL2ReverseRegistrar
    function setNameForAddr(address addr, string calldata name) external authorised(addr) {
        _setName(addr, name);
    }

    /// @inheritdoc IL2ReverseRegistrar
    function setNameForAddrWithSignature(
        NameClaim calldata claim,
        bytes calldata signature
    ) external {
        string memory chainIdsString = _validateChainIds(claim.chainIds);

        bytes32 message = _createNameForAddrWithSignatureMessageHash(claim, chainIdsString);
        _validateMessageAsNonce(message);

        signature.validateSignatureWithExpiry(claim.addr, message, claim.expirationTime);

        _setName(claim.addr, claim.name);
    }

    /// @inheritdoc IL2ReverseRegistrar
    function setNameForOwnableWithSignature(
        NameClaim calldata claim,
        address owner,
        bytes calldata signature
    ) external {
        string memory chainIdsString = _validateChainIds(claim.chainIds);

        if (!_ownsContract(claim.addr, owner)) revert NotOwnerOfContract();

        bytes32 message = _createNameForOwnableWithSignatureMessageHash(
            claim,
            owner,
            chainIdsString
        );
        _validateMessageAsNonce(message);

        signature.validateSignatureWithExpiry(owner, message, claim.expirationTime);

        _setName(claim.addr, claim.name);
    }

    /// @notice Checks if the provided contractAddr is a contract and is owned by the
    ///         provided addr.
    ///
    /// @param contractAddr The address of the contract to check.
    /// @param addr The address to check ownership against.
    function _ownsContract(address contractAddr, address addr) internal view returns (bool) {
        if (contractAddr.code.length == 0) return false;
        try Ownable(contractAddr).owner() returns (address owner) {
            return owner == addr;
        } catch {
            return false;
        }
    }

    function _validateMessageAsNonce(bytes32 messageHash) internal {
        if (_nonces[messageHash]) revert NonceAlreadyUsed();
        _nonces[messageHash] = true;
    }

    /// @notice Ensures the chain ids have matching names, and that the current chain id is included.
    ///
    /// @param chainIds The chain ids to check.
    /// @return chainIdsString The chain ids as a string.
    function _validateChainIds(
        uint256[] calldata chainIds
    ) internal view returns (string memory chainIdsString) {
        bool containsCurrentChain = false;

        for (uint256 i = 0; i < chainIds.length; ++i) {
            if (chainIds[i] == CHAIN_ID) containsCurrentChain = true;
            chainIdsString = string.concat(chainIdsString, Strings.toString(chainIds[i]));
            if (i < chainIds.length - 1) chainIdsString = string.concat(chainIdsString, ", ");
        }

        if (!containsCurrentChain) revert CurrentChainNotFound();

        return chainIdsString;
    }

    // struct ParsedClaimData {
    //     string addrString;
    //     string expiresAtString;
    //     string validatorAddressString;
    //     string nonceString;
    // }

    // function _parseSignatureData(
    //     NameClaim calldata claim
    // ) internal view returns (ParsedClaimData memory) {
    //     return
    //         ParsedClaimData({
    //             addrString: Strings.toChecksumHexString(claim.addr),
    //             expiresAtString: LibISO8601.toISO8601(claim.expirationTime),
    //             validatorAddressString: Strings.toChecksumHexString(address(this)),
    //             nonceString: Strings.toString(claim.nonce)
    //         });
    // }

    function _createNameForAddrWithSignatureMessageHash(
        NameClaim calldata claim,
        string memory chainIdsString
    ) internal view returns (bytes32 digest) {
        // Follow ERC191 version 0 https://eips.ethereum.org/EIPS/eip-191
        string memory name = claim.name;
        string memory addrString = Strings.toChecksumHexString(claim.addr);
        string memory expiresAtString = LibISO8601.toISO8601(claim.expirationTime);
        string memory validatorAddressString = Strings.toChecksumHexString(address(this));
        string memory nonceString = Strings.toString(claim.nonce);

        /*
        ```
        You are setting your ENS primary name to:
        {name}

        Address: {address}
        Chains: {chainList}
        Expires At: {expirationTime}

        ---
        Validator: {validatorAddress}
        Nonce: {nonce}
        ```
         */

        return
            abi
                .encodePacked(
                    "You are setting your ENS primary name to:\n",
                    name,
                    "\n\nAddress: ",
                    addrString,
                    "\nChains: ",
                    chainIdsString,
                    "\nExpires At: ",
                    expiresAtString,
                    "\n\n---\nValidator: ",
                    validatorAddressString,
                    "\nNonce: ",
                    nonceString
                )
                .toEthSignedMessageHash();

        // assembly {
        //     // free memory pointer
        //     let ptr := mload(0x40)
        //     // (32 bytes) store the string "You are setting your ENS primary"
        //     mstore(ptr, 0x596f75206172652073657474696e6720796f757220454e53207072696d617279)
        //     // (11 bytes) store the string " name to:\n"
        //     mstore(add(ptr, 32), 0x206e616d6520746f3a5c6e)
        //     // (? bytes) store claim.name
        //     let nameLength := mload(name)
        //     mcpy1(add(ptr, 43), add(name, 32), nameLength)
        //     // update ptr
        //     ptr := add(ptr, add(43, nameLength))
        //     // (13 bytes) store the string "\n\nAddress: "
        //     mstore(ptr, 0x5c6e5c6e416464726573733a20)
        //     // (? bytes) store claim.addr
        //     let addrLength := mload(addrString)
        //     mcpy1(add(ptr, 13), add(addrString, 32), addrLength)
        //     // update ptr
        //     ptr := add(ptr, add(13, addrLength))
        //     // (10 bytes) store the string "\nChains: "
        //     mstore(ptr, 0x5c6e436861696e733a20)
        //     // (? bytes) store chainIdsString
        //     let chainIdsStringLength := mload(chainIdsString)
        //     mcpy1(add(ptr, 10), add(chainIdsString, 32), chainIdsStringLength)
        //     // update ptr
        //     ptr := add(ptr, add(10, chainIdsStringLength))
        //     // (14 bytes) store the string "\nExpires At: "
        //     mstore(ptr, 0x5c6e457870697265732041743a20)
        //     // (20 bytes) store expiresAtString
        //     // TODO: check if this is correct
        //     mcpy1(add(ptr, 14), add(expiresAtString, 32), 20)
        //     // (20 bytes) store the string "\n\n---\nValidator: "
        //     mstore(add(ptr, 34), 0x5c6e5c6e2d2d2d5c6e56616c696461746f723a20)
        //     // (40 bytes) store validatorAddressString
        //     mcpy1(add(ptr, 54), add(validatorAddressString, 32), 40)
        //     // (9 bytes) store the string "\nNonce: "
        //     mstore(add(ptr, 94), 0x5c6e4e6f6e63653a20)
        //     // (? bytes) store nonceString
        //     let nonceLength := mload(nonceString)
        //     mcpy1(add(ptr, 103), add(nonceString, 32), nonceLength)
        //     // update ptr
        //     ptr := add(ptr, add(103, nonceLength))
        //     // create the message hash
        //     let messageHash := keccak256(0x40, ptr)
        //     mstore(ptr, "\x19Ethereum Signed Message:\n32") // 32 is the bytes-length of messageHash
        //     mstore(add(ptr, 0x1c), messageHash)
        //     digest := keccak256(ptr, 0x3c) // 0x3c is the length of the prefix (0x1c) + messageHash (0x20)

        //     function mcpy1(dst, src, len) {
        //         // Copy word-length chunks while possible
        //         // prettier-ignore
        //         for {} gt(len, 31) {} {
        //             mstore(dst, mload(src))
        //             dst := add(dst, 32)
        //             src := add(src, 32)
        //             len := sub(len, 32)
        //         }
        //         // Copy remaining bytes
        //         if len {
        //             let mask := sub(shl(shl(3, sub(32, len)), 1), 1)
        //             let wSrc := and(mload(src), not(mask))
        //             let wDst := and(mload(dst), mask)
        //             mstore(dst, or(wSrc, wDst))
        //         }
        //     }
        // }

        // return digest;
    }

    function _createNameForOwnableWithSignatureMessageHash(
        NameClaim calldata claim,
        address owner,
        string memory chainIdsString
    ) internal view returns (bytes32 digest) {
        string memory name = claim.name;
        string memory addrString = Strings.toChecksumHexString(claim.addr);
        string memory ownerString = Strings.toChecksumHexString(owner);
        string memory expiresAtString = LibISO8601.toISO8601(claim.expirationTime);
        string memory validatorAddressString = Strings.toChecksumHexString(address(this));
        string memory nonceString = Strings.toString(claim.nonce);

        /*
        ```
        You are setting the ENS primary name for a contract you own to:
        {name}

        Contract Address: {address}
        Owner: {owner}
        Chains: {chainList}
        Expires At: {expirationTime}

        ---
        Validator: {validatorAddress}
        Nonce: {nonce}
        ```
        */

        return
            abi
                .encodePacked(
                    "You are setting the ENS primary name for a contract you own to:\n",
                    name,
                    "\n\nContract Address: ",
                    addrString,
                    "\nOwner: ",
                    ownerString,
                    "\nChains: ",
                    chainIdsString,
                    "\nExpires At: ",
                    expiresAtString,
                    "\n\n---\nValidator: ",
                    validatorAddressString,
                    "\nNonce: ",
                    nonceString
                )
                .toEthSignedMessageHash();
    }
}
