// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @dev The data for inter-chain transfers of a name.
 * This will be passed in the data field of the ERC721Received, ERC1155Received, ERC1155BatchReceived calls.
 */
struct TransferData {
    string label;
    address owner;
    address subregistry;
    address resolver;
    uint256 roleBitmap;
    uint64 expires;
}
