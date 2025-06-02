// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";
import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";
import {IDedicatedResolver, NODE_ANY} from "./IDedicatedResolver.sol";
import {IRegistryTraversal} from "./IRegistryTraversal.sol";
import {ENSIP19, COIN_TYPE_ETH, EVM_BIT} from "@ens/contracts/utils/ENSIP19.sol";
import {AddrUtils} from "./AddrUtils.sol";

// Resolver profile interfaces
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
    error UnreachableName(bytes name);

    error UnsupportedResolverProfile(bytes4 selector);

    error InvalidContentType(uint256 contentType);

    /// @dev The UniversalResolver address was changed.
    /// @param _universalResolver The new address.
    event UniversalResolverChanged(address indexed _universalResolver);

    // Mapping from coin type to address
    mapping(uint256 => bytes) private _addresses;

    // Mapping from key to text value
    mapping(string => string) private _texts;

    // Content hash
    bytes private _contenthash;

    // Public key
    struct PublicKey {
        bytes32 x;
        bytes32 y;
    }

    PublicKey private _pubkey;

    // Mapping from content type to ABI
    mapping(uint256 => bytes) private _abis;

    // Mapping from interface ID to implementer
    mapping(bytes4 => address) private _interfaces;

    // Name
    string private _primary;

    // Wildcard and UniversalResolver
    bool public wildcard;
    address public universalResolver;

    /**
     * @dev Initializes the contract with an owner and associated name
     * @param owner The owner of the resolver
     * @param _wildcard True if the resolver should answer for any name.
     * @param _universalResolver The address of the Universal Resolver.
     */
    function initialize(address owner, bool _wildcard, address _universalResolver) public initializer {
        __Ownable_init(owner);
        wildcard = _wildcard;
        _setUniversalResolver(_universalResolver);
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165) returns (bool) {
        return interfaceId == type(IExtendedResolver).interfaceId || interfaceId == type(IDedicatedResolver).interfaceId
            || interfaceId == this.multicall.selector || super.supportsInterface(interfaceId);
    }

    function _setUniversalResolver(address ur) internal {
        universalResolver = ur;
        emit UniversalResolverChanged(ur);
    }

    /// @notice Set the Universal Resolver address.
    /// @param _universalResolver The new address.
    function setUniversalResolver(address _universalResolver) external onlyOwner {
        _setUniversalResolver(_universalResolver);
    }

    /// @notice Set address for the coin type.
    /// @param coinType The coin type.
    /// @param addressBytes The address to set.
    function setAddr(uint256 coinType, bytes calldata addressBytes) external onlyOwner {
        _addresses[coinType] = addressBytes;
        emit AddressChanged(NODE_ANY, coinType, addressBytes);
        if (coinType == COIN_TYPE_ETH) {
            emit AddrChanged(NODE_ANY, AddrUtils.toAddr(addressBytes));
        }
    }

    /// @notice Get the address for coin type.
    ///         If an EVM and empty, defaults to `addr(EVM_BIT)`.
    /// @param coinType The coin type.
    /// @return addressBytes The address for the coin type.
    function addr(bytes32, uint256 coinType) public view returns (bytes memory addressBytes) {
        addressBytes = _addresses[coinType];
        if (addressBytes.length == 0 && ENSIP19.chainFromCoinType(coinType) > 0) {
            addressBytes = _addresses[EVM_BIT];
        }
    }

    /// @notice `addr(60)` as `address`.
    function addr(bytes32) public view returns (address payable) {
        return payable(AddrUtils.toAddr(addr(NODE_ANY, COIN_TYPE_ETH)));
    }

    /// @notice Determine if coin type has been set explicitly.
    function hasAddr(uint256 coinType) external view returns (bool) {
        return _addresses[coinType].length > 0;
    }

    /// @notice Set a text record.
    /// @param key The key to set.
    /// @param value The value to set.
    function setText(string calldata key, string calldata value) external onlyOwner {
        _texts[key] = value;
        emit TextChanged(NODE_ANY, key, key, value);
    }

    /// @notice Get the text value for key.
    /// @param key The key.
    /// @return value The text value.
    function text(bytes32, string memory key) external view returns (string memory value) {
        value = _texts[key];
    }

    /// @notice Set the content hash.
    /// @param hash The content hash.
    function setContenthash(bytes calldata hash) external onlyOwner {
        _contenthash = hash;
        emit ContenthashChanged(NODE_ANY, hash);
    }

    /// @notice Get the content hash.
    function contenthash(bytes32) external view returns (bytes memory) {
        return _contenthash;
    }

    /// @dev Sets the public key.
    /// @param x The x coordinate of the pubkey.
    /// @param y The y coordinate of the pubkey.
    function setPubkey(bytes32 x, bytes32 y) external onlyOwner {
        _pubkey = PublicKey(x, y);
        emit PubkeyChanged(NODE_ANY, x, y);
    }

    /// @dev Get the public key.
    /// @return x The x coordinate of the public key.
    /// @return y The y coordinate of the public key.
    function pubkey(bytes32) external view returns (bytes32 x, bytes32 y) {
        x = _pubkey.x;
        y = _pubkey.y;
    }

    /// @dev Set the ABI for the content type.
    /// @param contentType The content type.
    /// @param data The ABI data.
    function setABI(uint256 contentType, bytes calldata data) external onlyOwner {
        if (contentType == 0 || (contentType - 1) & contentType != 0) {
            revert InvalidContentType(contentType);
        }
        _abis[contentType] = data;
        emit ABIChanged(NODE_ANY, contentType);
    }

    /// @dev Get the first ABI for the specified content types.
    /// @param contentTypes Union of desired contents types.
    /// @return contentType The first matching content type (or 0 if no match).
    /// @return data The encoded ABI.
    function ABI(bytes32, uint256 contentTypes) public view returns (uint256 contentType, bytes memory data) {
        for (contentType = 1; contentType > 0 && contentType <= contentTypes; contentType <<= 1) {
            if ((contentType & contentTypes) != 0) {
                data = _abis[contentType];
                if (data.length > 0) {
                    return (contentType, data);
                }
            }
        }
        return (0, "");
    }

    /**
     * @dev Sets the implementer for an interface
     * @param interfaceId The interface ID.
     * @param implementer The implementer address.
     */
    function setInterface(bytes4 interfaceId, address implementer) external onlyOwner {
        _interfaces[interfaceId] = implementer;
        emit InterfaceChanged(NODE_ANY, interfaceId, implementer);
    }

    /// @dev Gets the implementer for an interface.
    /// @param interfaceId The interface ID.
    /// @return implementer The implementer address.
    function interfaceImplementer(bytes32, bytes4 interfaceId) public view returns (address implementer) {
        implementer = _interfaces[interfaceId];
        if (implementer == address(0) && ERC165Checker.supportsInterface(addr(NODE_ANY), interfaceId)) {
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
    /// @return name_ The primary name.
    function name(bytes32) external view returns (string memory name_) {
        name_ = _primary;
    }

    /// @dev True if `wildcard` or this resolver is exact in the registry.
    /// @inheritdoc IDedicatedResolver
    function supportsName(bytes memory _name) public view returns (bool) {
        if (wildcard) return true;
        if (address(universalResolver) == address(0)) return false;
        (address resolver,, uint256 offset) = IRegistryTraversal(universalResolver).findResolver(_name);
        return resolver == address(this) && offset == 0;
    }

    function resolve(bytes calldata _name, bytes calldata data) external view returns (bytes memory) {
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
        // bytes4 selector = bytes4(data);
        // if (selector == IAddrResolver.addr.selector) {
        //     return abi.encode(_toAddr(addr(NODE_ANY, COIN_TYPE_ETH)));
        // } else if (selector == IAddressResolver.addr.selector) {
        //     (, uint256 coinType) = abi.decode(data[4:], (bytes32, uint256));
        //     return abi.encode(addr(NODE_ANY, coinType));
        // } else if (selector == ITextResolver.text.selector) {
        //     (, string memory key) = abi.decode(data[4:], (bytes32, string));
        //     return abi.encode(_texts[key]);
        // } else if (selector == IContentHashResolver.contenthash.selector) {
        //     return abi.encode(_contenthash);
        // } else if (selector == IPubkeyResolver.pubkey.selector) {
        //     return abi.encode(_pubkey);
        // } else if (selector == INameResolver.name.selector) {
        //     return abi.encode(_primary);
        // } else if (selector == IInterfaceResolver.interfaceImplementer.selector) {
        //     (, bytes4 interfaceId) = abi.decode(data[4:], (bytes32, bytes4));
        //     return abi.encode(interfaceImplementer(NODE_ANY, interfaceId));
        // } else if (selector == IABIResolver.ABI.selector) {
        //     (, uint256 contentTypes) = abi.decode(data[4:], (bytes32, uint256));
        //     (uint256 contentType, bytes memory v) = ABI(NODE_ANY, contentType);
        //     return abi.encode(contentType, v);
        // } else {
        //     revert UnsupportedResolverProfile(selector);
        // }
    }

    function multicall(bytes[] calldata calls) external returns (bytes[] memory results) {
        results = new bytes[](calls.length);
        for (uint256 i; i < calls.length; i++) {
            (bool ok, bytes memory v) = address(this).delegatecall(calls[i]);
            require(ok);
            results[i] = v;
        }
        return results;
    }
}
