// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

event LabelHashPreimage(uint256 indexed labelHash, string label);

interface IPreimageDatastore {
    function label(
        uint256 labelHash
    ) external view returns (string memory label);
    function setLabel(string memory label) external;
}
