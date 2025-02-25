// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IPreimageDatastore, LabelHashPreimage} from "./IPreimageDatastore.sol";

contract PreimageDatastore is IPreimageDatastore {
    mapping(uint256 labelhash => string label) public label;

    function setLabel(string memory _label) external {
        uint256 labelHash = uint256(keccak256(bytes(_label)));
        if (bytes(label[labelHash]).length == 0) {
            label[labelHash] = _label;
            emit LabelHashPreimage(labelHash, _label);
        }
    }
}
