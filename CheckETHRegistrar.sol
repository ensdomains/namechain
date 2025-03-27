// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

interface IRegistry {
}

interface IMockETHRegistrar {
    function makeCommitment(
        string calldata name,
        address owner,
        bytes32 secret,
        address subregistry,
        address resolver,
        uint96 flags,
        uint64 duration
    ) external pure returns (bytes32);
    
    function register(
        string calldata name,
        address owner,
        bytes32 secret,
        IRegistry subregistry,
        address resolver,
        uint96 flags,
        uint64 duration
    ) external payable returns (uint256);
}

contract CheckETHRegistrar {
    // This function will only compile if the makeCommitment function signature matches
    function testMakeCommitmentSignature(IMockETHRegistrar registrar) public pure {
        registrar.makeCommitment(
            "test",
            address(0),
            bytes32(0),
            address(0),
            address(0),
            0,
            0
        );
    }
    
    // This function will only compile if the register function signature matches
    function testRegisterSignature(IMockETHRegistrar registrar) public {
        registrar.register{value: 0}(
            "test",
            address(0),
            bytes32(0),
            IRegistry(address(0)),
            address(0),
            0,
            0
        );
    }
} 