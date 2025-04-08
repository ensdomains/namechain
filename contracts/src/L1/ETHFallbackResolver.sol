// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {GatewayFetcher} from "@unruggable/gateways/contracts/GatewayFetcher.sol";
import {GatewayRequest, EvalFlag} from "@unruggable/gateways/contracts/GatewayRequest.sol";
import {GatewayFetchTarget, IGatewayVerifier} from "@unruggable/gateways/contracts/GatewayFetchTarget.sol";
import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";
import {IAddrResolver} from "@ens/contracts/resolvers/profiles/IAddrResolver.sol";
import {IAddressResolver} from "@ens/contracts/resolvers/profiles/IAddressResolver.sol";
import {ITextResolver} from "@ens/contracts/resolvers/profiles/ITextResolver.sol";
import {IContentHashResolver} from "@ens/contracts/resolvers/profiles/IContentHashResolver.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {DatastoreUtils} from "../common/DatastoreUtils.sol";
import {IRegistryDatastore} from "../common/IRegistryDatastore.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {BytesUtils} from "@ens/contracts/utils/BytesUtils.sol";

contract ETHFallbackResolver is IExtendedResolver, GatewayFetchTarget, ERC165 {
    using GatewayFetcher for GatewayRequest;

    IRegistry public immutable ethRegistry;
    address public immutable namechainDatastore;
    address public immutable namechainRootRegistry;
    IGatewayVerifier public immutable namechainVerifier;

    bytes constant DOT_ETH_SUFFIX = "\x03eth\x00";

    // storage layout of RegistryDatastore
    uint256 constant SLOT_RD_ENTRIES = 0;

    // storage layout of PublicResolver
    uint256 constant SLOT_PR_VERSIONS = 0;
    uint256 constant SLOT_PR_ADDRESSES = 2;
    uint256 constant SLOT_PR_CONTENTHASHES = 3;
    uint256 constant SLOT_PR_TEXTS = 10;

    /// @param name DNS-encoded ENS name that does not exist.
    error UnreachableName(bytes name);

    /// @param selector Function selector of the resolver profile that cannot be answered.
    error UnsupportedResolverProfile(bytes4 selector);

    constructor(
        IRegistry _ethRegistry,
        address _namechainDatastore,
        address _namechainRootRegistry,
        IGatewayVerifier _namechainVerifier
    ) {
        ethRegistry = _ethRegistry;
        namechainDatastore = _namechainDatastore;
        namechainRootRegistry = _namechainRootRegistry;
        namechainVerifier = _namechainVerifier;
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceID
    ) public view virtual override(ERC165) returns (bool) {
        return
            type(IExtendedResolver).interfaceId == interfaceID ||
            super.supportsInterface(interfaceID);
    }

    /// @dev Parse `"\x01a\x02bb\x03ccc\x03eth\x00"` into `[0, 2, 5]`.
    ///      Reverts if not ".eth" or the name is invalid.
    ///      Returns [] for "eth".
    /// @param name The name to parse.
    /// @return offsets The byte-offsets of each label excluding ".eth".
    function _parseName(
        bytes calldata name
    ) internal pure returns (uint256[] memory offsets) {
        uint256 offset;
        uint256 count;
        //while (uint8(name[offset]) > 0) {
        while (true) {
            if (BytesUtils.equals(name[offset:], DOT_ETH_SUFFIX)) {
                break;
            }
            if (count == offsets.length) {
                uint256[] memory v = new uint256[](count + 8);
                for (uint256 i; i < count; i++) {
                    v[i] = offsets[i];
                }
                offsets = v;
            }
            offsets[count++] = offset;
            (, offset) = NameCoder.readLabel(name, offset);
        }
        assembly {
            mstore(offsets, count)
        }
    }

	/// @dev Create program to traverse RegistryDatastore.
    function _findResolverProgram() internal pure returns (GatewayRequest memory req) {
        req = GatewayFetcher.newCommand();
        req.pushOutput(0); // parent registry
        req.setSlot(SLOT_RD_ENTRIES);
        req.follow().follow(); // entry[registry][labelHash]
        req.read().shl(96).shr(96); // read registry
        req.offset(1).read().shl(96).shr(96); // read resolver
        req.push(GatewayFetcher.newCommand().requireNonzero(1).setOutput(1)); // save resolver if set
        req.evalLoop(0, 1);
        req.requireNonzero(1).setOutput(0); // require registry and save it
    }

    /// @inheritdoc IExtendedResolver
    function resolve(
        bytes calldata name,
        bytes calldata data
    ) external view returns (bytes memory) {
        uint256[] memory offsets = _parseName(name);
        if (offsets.length == 0) {
            revert UnreachableName(name); // no records on "eth"
        }
        address resolver = ethRegistry.getResolver(
            NameUtils.readLabel(name, offsets[offsets.length - 1])
        );
        if (resolver != address(0) && resolver != address(this)) {
            revert UnreachableName(name); // invalid state: ejected and resolver exists and different from us
        }
        GatewayRequest memory req = GatewayFetcher.newRequest(2);
        req.setTarget(namechainDatastore);
        req.setSlot(SLOT_RD_ENTRIES);
        for (uint256 i; i < offsets.length; i++) {
            (bytes32 labelHash, ) = NameCoder.readLabel(name, offsets[i]);
            req.push(DatastoreUtils.normalizeLabelHash(uint256(labelHash)));
        }
        req.push(DatastoreUtils.normalizeLabelHash(uint256(keccak256("eth"))));
        req.push(namechainRootRegistry).setOutput(0); // start at root
        req.push(_findResolverProgram());
        req.evalLoop(EvalFlag.STOP_ON_FAILURE); // outputs = [registry, resolver]
        req.pushOutput(1).requireNonzero(2).target(); // target resolver
        req.push(NameCoder.namehash(name, 0)); // node, leave on stack at offset 0
        req.setSlot(SLOT_PR_VERSIONS); // recordVersions
        req.pushStack(0).follow(); // recordVersions[node]
        req.read(); // version, leave on stack at offset 1
        if (bytes4(data) == IAddrResolver.addr.selector) {
            req.setSlot(SLOT_PR_ADDRESSES);
			req.follow(); // addr[version]
            req.follow(); // addr[version][node]
            req.push(60).follow(); // addr[version][node][60]
            req.readBytes().setOutput(1);
        } else if (bytes4(data) == IAddressResolver.addr.selector) {
            (, uint256 coinType) = abi.decode(data[4:], (bytes32, uint256));
            req.setSlot(SLOT_PR_ADDRESSES);
            req.follow(); // addr[version]
            req.follow(); // addr[version][node]
            req.push(coinType).follow(); // addr[version][node][coinType]
            req.readBytes().setOutput(1);
        } else if (bytes4(data) == ITextResolver.text.selector) {
            (, string memory key) = abi.decode(data[4:], (bytes32, string));
            req.setSlot(SLOT_PR_TEXTS);
            req.follow(); // text[version]
            req.follow(); // text[version][node]
            req.push(key).follow(); // text[version][node][key]
            req.readBytes().setOutput(1);
        } else {
            revert UnsupportedResolverProfile(bytes4(data));
        }
        fetch(
            namechainVerifier,
            req,
            this.resolveCallback.selector,
            data,
            new string[](0)
        );
    }

    function resolveCallback(
        bytes[] memory values,
        uint8 /*exitCode*/,
        bytes memory data
    ) external pure returns (bytes memory) {
        // exitCode == 2 => no resolver
        bytes memory value = values[1];
        if (bytes4(data) == IAddrResolver.addr.selector) {
            return abi.encode(address(bytes20(value)));
        } else {
            return abi.encode(value);
        }
    }
}
