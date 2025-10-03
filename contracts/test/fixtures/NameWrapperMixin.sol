// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";

import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {
    BaseRegistrarImplementation
} from "@ens/contracts/ethregistrar/BaseRegistrarImplementation.sol";
import {ENSRegistry} from "@ens/contracts/registry/ENSRegistry.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {NameWrapper, IMetadataService} from "@ens/contracts/wrapper/NameWrapper.sol";

import {NameUtils} from "../../src/common/NameUtils.sol";

abstract contract NameWrapperMixin is Test, ERC721Holder, ERC1155Holder {
    ENSRegistry ensV1;
    BaseRegistrarImplementation ethRegistrarV1;
    NameWrapper nameWrapper;

    address user = makeAddr("user");

    function deployNameWrapper() internal {
        ensV1 = new ENSRegistry();
        ethRegistrarV1 = new BaseRegistrarImplementation(ensV1, NameUtils.ETH_NODE);
        claimNodes(NameCoder.encode("eth"), 0, address(ethRegistrarV1));
        claimNodes(NameCoder.encode("addr.reverse"), 0, address(this));
        ethRegistrarV1.addController(address(this));
        nameWrapper = new NameWrapper(ensV1, ethRegistrarV1, IMetadataService(address(0)));
        vm.warp(ethRegistrarV1.GRACE_PERIOD() + 1); // avoid timestamp issues
    }

    // fake ReverseClaimer
    function claim(address) external pure returns (bytes32) {}

    function claimNodes(bytes memory name, uint256 offset, address owner) internal {
        bytes32 labelHash;
        (labelHash, offset, , ) = NameCoder.readLabel(name, offset, false);
        if (labelHash != bytes32(0)) {
            claimNodes(name, offset, owner);
            ensV1.setSubnodeOwner(NameCoder.namehash(name, offset), labelHash, owner);
        }
    }

    function registerUnwrapped(
        string memory label
    ) public returns (bytes memory name, uint256 tokenId) {
        name = NameUtils.appendETH(label);
        tokenId = uint256(keccak256(bytes(label)));
        ethRegistrarV1.register(tokenId, user, 86400); // test duration
        assertEq(ethRegistrarV1.ownerOf(tokenId), user, "owner");
    }

    function registerWrappedETH2LD(
        string memory label,
        uint32 ownerFuses
    ) public returns (bytes memory name, uint256 tokenId) {
        (name, tokenId) = registerUnwrapped(label);
        address owner = ethRegistrarV1.ownerOf(tokenId);
        vm.startPrank(owner);
        ethRegistrarV1.setApprovalForAll(address(nameWrapper), true);
        nameWrapper.wrapETH2LD(label, owner, uint16(ownerFuses), address(0));
        vm.stopPrank();
        tokenId = uint256(NameCoder.namehash(NameUtils.ETH_NODE, bytes32(tokenId)));
        assertEq(nameWrapper.ownerOf(tokenId), user, "owner");
    }

    function createWrappedChild(
        uint256 parentTokenId,
        string memory label,
        uint32 fuses
    ) internal returns (bytes memory name, uint256 tokenId) {
        bytes memory parentName = nameWrapper.names(bytes32(parentTokenId));
        (address owner, , uint64 expiry) = nameWrapper.getData(parentTokenId);
        name = NameUtils.append(parentName, label);
        vm.prank(owner);
        tokenId = uint256(
            nameWrapper.setSubnodeOwner(bytes32(parentTokenId), label, owner, fuses, expiry)
        );
    }

    function createWrappedName(
        string memory domain,
        uint32 fuses
    ) internal returns (bytes memory name, uint256 tokenId) {
        name = NameCoder.encode(domain);
        claimNodes(name, 0, address(this));
        (bytes32 labelHash, uint256 offset, , ) = NameCoder.readLabel(name, 0, false);
        bytes32 parentNode = NameCoder.namehash(name, offset);
        ensV1.setApprovalForAll(address(nameWrapper), true);
        nameWrapper.wrap(name, user, address(0));
        tokenId = uint256(NameCoder.namehash(parentNode, labelHash));
        vm.prank(user);
        nameWrapper.setFuses(bytes32(tokenId), uint16(fuses));
    }
}
