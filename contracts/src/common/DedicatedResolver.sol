// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {IDedicatedResolver, NODE_ANY} from "./IDedicatedResolver.sol";
import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";
import {IMulticallable} from "@ens/contracts/resolvers/IMulticallable.sol";
import {IResolverFinder} from "./IResolverFinder.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {ENSIP19, COIN_TYPE_ETH, EVM_BIT} from "@ens/contracts/utils/ENSIP19.sol";

// resolver profiles
import {IAddrResolver} from "@ens/contracts/resolvers/profiles/IAddrResolver.sol";
import {IAddressResolver} from "@ens/contracts/resolvers/profiles/IAddressResolver.sol";
import {ITextResolver} from "@ens/contracts/resolvers/profiles/ITextResolver.sol";
import {IContentHashResolver} from "@ens/contracts/resolvers/profiles/IContentHashResolver.sol";
import {IPubkeyResolver} from "@ens/contracts/resolvers/profiles/IPubkeyResolver.sol";
import {INameResolver} from "@ens/contracts/resolvers/profiles/INameResolver.sol";
import {IABIResolver} from "@ens/contracts/resolvers/profiles/IABIResolver.sol";
import {IInterfaceResolver} from "@ens/contracts/resolvers/profiles/IInterfaceResolver.sol";

/// @title DedicatedResolver
/// @notice An owned resolver that provides the same results for any name.
///         If `wildcard` is false, it only supports names registered exactly with matching resolver.
///         This is equivalent to `findResolver(name)` where `resolver == this && offset == 0`.
contract DedicatedResolver is
    ERC165,
    OwnableUpgradeable,
    IExtendedResolver,
    IDedicatedResolver,
    IAddrResolver,
    IAddressResolver,
    ITextResolver,
    IContentHashResolver,
    IPubkeyResolver,
    INameResolver,
    IABIResolver,
    IInterfaceResolver
{
    // profile storage
    mapping(uint256 => bytes) private _addresses;
    mapping(string => string) private _texts;
    bytes private _contenthash;
    bytes32 private _pubkeyX;
    bytes32 private _pubkeyY;
    mapping(uint256 => bytes) private _abis;
    mapping(bytes4 => address) private _interfaces;
    string private _primary;

    /// @notice True if the resolver supports any name.
    bool public wildcard;

    /// @notice The resolver profile cannot be answered.
    /// @dev Error selector: `0x5fe9a5df`
    error UnsupportedResolverProfile(bytes4 selector);

    /// @notice The supplied name is not supported by this resolver.
    /// @dev Error selector: `0x5fe9a5df`
    error UnreachableName(bytes name);

    /// @notice The coin type is not a power of 2.
    /// @dev Error selector: `0xe7cf0ac4`
    error InvalidContentType(uint256 contentType);

    /// @notice The address could not be converted to `address`.
    /// @dev Error selector: `0x8d666f60`
    error InvalidEVMAddress(bytes addressBytes);

    /// @notice An `IResolverFinder` implementation is required.
    /// @dev Error selector: `0x918c3b04`
    error ResolverFinderRequired();

    /// @notice A `DedicatedResolver` was created.
    /// @dev Error selector: `0xa586da65`
    event NewDediciatedResolver(address owner, bool wildcard);

    constructor(address owner, bool _wildcard, address _resolverFinder) {
        initialize(owner, _wildcard, _resolverFinder);
    }

    /// @dev Initialize the contract.
    /// @param owner The owner of the resolver.
    /// @param _wildcard True if the resolver should support for any name.
    /// @param _resolverFinder An optional contract that implements `IResolverFinder`.
    function initialize(
        address owner,
        bool _wildcard,
        address _resolverFinder
    ) public initializer {
        __Ownable_init(owner);
        wildcard = _wildcard;
        emit NewDediciatedResolver(owner, _wildcard);
        if (_resolverFinder != address(0)) {
            _setInterface(type(IResolverFinder).interfaceId, _resolverFinder);
        }
    }

    /// @inheritdoc ERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165) returns (bool) {
        return
            type(IExtendedResolver).interfaceId == interfaceId ||
            type(IDedicatedResolver).interfaceId == interfaceId ||
            type(IMulticallable).interfaceId == interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @notice Get the `IResolverFinder` implementation.
    ///         Defaults to the proxy implementation if unset.
    /// @return The `IResolverFinder` implementation.
    function resolverFinder() public view returns (IResolverFinder) {
        address impl = interfaceImplementer(
            NODE_ANY,
            type(IResolverFinder).interfaceId
        );
        if (impl != address(0)) {
            return IResolverFinder(impl);
        }
        address base = ERC1967Utils.getImplementation();
        if (base == address(0)) {
            revert ResolverFinderRequired();
        }
        return DedicatedResolver(base).resolverFinder();
    }

    /// @notice Set address for the coin type.
    ///         If coin type is EVM, require exactly 0 or 20 bytes.
    /// @param coinType The coin type.
    /// @param addressBytes The address to set.
    function setAddr(
        uint256 coinType,
        bytes memory addressBytes
    ) external onlyOwner {
        if (
            addressBytes.length != 0 &&
            addressBytes.length != 20 &&
            ENSIP19.isEVMCoinType(coinType)
        ) {
            revert InvalidEVMAddress(addressBytes);
        }
        _addresses[coinType] = addressBytes;
        emit AddressChanged(NODE_ANY, coinType, addressBytes);
        if (coinType == COIN_TYPE_ETH) {
            emit AddrChanged(NODE_ANY, address(bytes20(addressBytes)));
        }
    }

    /// @notice Get the address for coin type.
    ///         If coin type is EVM and empty, defaults to `addr(EVM_BIT)`.
    /// @param coinType The coin type.
    /// @return addressBytes The address for the coin type.
    function addr(
        bytes32,
        uint256 coinType
    ) public view returns (bytes memory addressBytes) {
        addressBytes = _addresses[coinType];
        if (
            addressBytes.length == 0 && ENSIP19.chainFromCoinType(coinType) > 0
        ) {
            addressBytes = _addresses[EVM_BIT];
        }
    }

    /// @notice Get `addr(60)` as `address`.
    /// @return The address for coin type 60.
    function addr(bytes32) public view returns (address payable) {
        return payable(address(bytes20(addr(NODE_ANY, COIN_TYPE_ETH))));
    }

    /// @notice Determine if coin type has been set explicitly.
    /// @param coinType The coin type.
    /// @return True if `setAddr(node, coinType)` has been set.
    function hasAddr(bytes32, uint256 coinType) external view returns (bool) {
        return _addresses[coinType].length > 0;
    }

    /// @notice Set a text record.
    /// @param key The key to set.
    /// @param value The value to set.
    function setText(
        string calldata key,
        string calldata value
    ) external onlyOwner {
        _texts[key] = value;
        emit TextChanged(NODE_ANY, key, key, value);
    }

    /// @notice Get the text value for key.
    /// @param key The key.
    /// @return The text value.
    function text(
        bytes32,
        string memory key
    ) external view returns (string memory) {
        return _texts[key];
    }

    /// @notice Set the content hash.
    /// @param hash The content hash.
    function setContenthash(bytes calldata hash) external onlyOwner {
        _contenthash = hash;
        emit ContenthashChanged(NODE_ANY, hash);
    }

    /// @notice Get the content hash.
    /// @return The contenthash.
    function contenthash(bytes32) external view returns (bytes memory) {
        return _contenthash;
    }

    /// @dev Sets the public key.
    /// @param x The x coordinate of the pubkey.
    /// @param y The y coordinate of the pubkey.
    function setPubkey(bytes32 x, bytes32 y) external onlyOwner {
        _pubkeyX = x;
        _pubkeyY = y;
        emit PubkeyChanged(NODE_ANY, x, y);
    }

    /// @dev Get the public key.
    /// @return x The x coordinate of the public key.
    /// @return y The y coordinate of the public key.
    function pubkey(bytes32) external view returns (bytes32 x, bytes32 y) {
        x = _pubkeyX;
        y = _pubkeyY;
    }

    /// @dev Set the ABI for the content type.
    /// @param contentType The content type.
    /// @param data The ABI data.
    function setABI(
        uint256 contentType,
        bytes calldata data
    ) external onlyOwner {
        if (contentType == 0 || (contentType - 1) & contentType != 0) {
            revert InvalidContentType(contentType);
        }
        _abis[contentType] = data;
        emit ABIChanged(NODE_ANY, contentType);
    }

    /// @dev Get the first ABI for the specified content types.
    /// @param contentTypes Union of desired contents types.
    /// @return contentType The first matching content type (or 0 if no match).
    /// @return data The ABI data.
    function ABI(
        bytes32,
        uint256 contentTypes
    ) public view returns (uint256 contentType, bytes memory data) {
        for (
            contentType = 1;
            contentType > 0 && contentType <= contentTypes;
            contentType <<= 1
        ) {
            if ((contentType & contentTypes) != 0) {
                data = _abis[contentType];
                if (data.length > 0) {
                    return (contentType, data);
                }
            }
        }
        return (0, "");
    }

    /// @dev Sets the implementer for an interface.
    /// @param interfaceId The interface ID.
    /// @param implementer The implementer address.
    function setInterface(
        bytes4 interfaceId,
        address implementer
    ) public onlyOwner {
        _setInterface(interfaceId, implementer);
    }

    function _setInterface(bytes4 interfaceId, address implementer) private {
        _interfaces[interfaceId] = implementer;
        emit InterfaceChanged(NODE_ANY, interfaceId, implementer);
    }

    /// @dev Gets the implementer for an interface.
    /// @param interfaceId The interface ID.
    /// @return implementer The implementer address.
    function interfaceImplementer(
        bytes32,
        bytes4 interfaceId
    ) public view returns (address implementer) {
        implementer = _interfaces[interfaceId];
        if (
            implementer == address(0) &&
            ERC165Checker.supportsInterface(addr(NODE_ANY), interfaceId)
        ) {
            implementer = address(this);
        }
    }

    /// @dev Set the primary name.
    /// @param _name The primary name.
    function setName(string calldata _name) external onlyOwner {
        _primary = _name;
        emit NameChanged(NODE_ANY, _name);
    }

    /// @dev Get the primary name.
    /// @return The primary name.
    function name(bytes32) external view returns (string memory) {
        return _primary;
    }

    /// @inheritdoc IDedicatedResolver
    /// @dev True if `wildcard` or this resolver is exact in the registry.
    function supportsName(bytes memory _name) public view returns (bool) {
        if (wildcard) return true;
        (address resolver, , uint256 offset) = resolverFinder().findResolver(
            _name
        );
        return resolver == address(this) && offset == 0;
    }

    function resolve(
        bytes calldata _name,
        bytes calldata data
    ) external view returns (bytes memory) {
        if (!supportsName(_name)) {
            revert UnreachableName(_name);
        }
        (bool ok, bytes memory v) = address(this).staticcall(data);
        if (!ok) {
            assembly {
                revert(add(v, 32), mload(v))
            }
        } else if (v.length == 0) {
            revert UnsupportedResolverProfile(bytes4(data));
        }
        return v;
    }

    function multicall(
        bytes[] calldata calls
    ) public returns (bytes[] memory results) {
        results = new bytes[](calls.length);
        for (uint256 i; i < calls.length; i++) {
            (bool ok, bytes memory v) = address(this).delegatecall(calls[i]);
            require(ok);
            results[i] = v;
        }
        return results;
    }

    /// @notice Warning: node check is ignored.
    function multicallWithNodeCheck(
        bytes32,
        bytes[] calldata calls
    ) external returns (bytes[] memory) {
        return multicall(calls);
    }
}
