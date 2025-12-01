// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IMulticallable} from "@ens/contracts/resolvers/IMulticallable.sol";
import {IABIResolver} from "@ens/contracts/resolvers/profiles/IABIResolver.sol";
import {IAddressResolver} from "@ens/contracts/resolvers/profiles/IAddressResolver.sol";
import {IAddrResolver} from "@ens/contracts/resolvers/profiles/IAddrResolver.sol";
import {IContentHashResolver} from "@ens/contracts/resolvers/profiles/IContentHashResolver.sol";
import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";
import {IHasAddressResolver} from "@ens/contracts/resolvers/profiles/IHasAddressResolver.sol";
import {IInterfaceResolver} from "@ens/contracts/resolvers/profiles/IInterfaceResolver.sol";
import {INameResolver} from "@ens/contracts/resolvers/profiles/INameResolver.sol";
import {IPubkeyResolver} from "@ens/contracts/resolvers/profiles/IPubkeyResolver.sol";
import {ITextResolver} from "@ens/contracts/resolvers/profiles/ITextResolver.sol";
import {ResolverFeatures} from "@ens/contracts/resolvers/ResolverFeatures.sol";
import {ENSIP19, COIN_TYPE_ETH, COIN_TYPE_DEFAULT} from "@ens/contracts/utils/ENSIP19.sol";
import {IERC7996} from "@ens/contracts/utils/IERC7996.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {EnhancedAccessControl} from "../access-control/EnhancedAccessControl.sol";
import {InvalidOwner} from "../CommonErrors.sol";
import {HCAContext} from "../hca/HCAContext.sol";
import {HCAContextUpgradeable} from "../hca/HCAContextUpgradeable.sol";
import {HCAEquivalence} from "../hca/HCAEquivalence.sol";
import {IHCAFactoryBasic} from "../hca/interfaces/IHCAFactoryBasic.sol";

import {IDedicatedResolverSetters, NODE_ANY} from "./interfaces/IDedicatedResolverSetters.sol";
import {DedicatedResolverLib} from "./libraries/DedicatedResolverLib.sol";

/// @notice An owned resolver that provides the same results for any name.
contract DedicatedResolver is
    HCAContextUpgradeable,
    UUPSUpgradeable,
    EnhancedAccessControl,
    IDedicatedResolverSetters,
    IERC7996,
    IExtendedResolver,
    IMulticallable,
    IAddrResolver,
    IAddressResolver,
    IHasAddressResolver,
    ITextResolver,
    IContentHashResolver,
    IPubkeyResolver,
    INameResolver,
    IABIResolver,
    IInterfaceResolver
{
    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    /// @notice The resolver profile cannot be answered.
    /// @dev Error selector: `0x7b1c461b`
    error UnsupportedResolverProfile(bytes4 selector);

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(IHCAFactoryBasic hcaFactory) HCAEquivalence(hcaFactory) {
        _disableInitializers();
    }

    /// @inheritdoc EnhancedAccessControl
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(EnhancedAccessControl) returns (bool) {
        return
            type(IExtendedResolver).interfaceId == interfaceId ||
            type(IDedicatedResolverSetters).interfaceId == interfaceId ||
            type(IMulticallable).interfaceId == interfaceId ||
            type(IAddrResolver).interfaceId == interfaceId ||
            type(IAddressResolver).interfaceId == interfaceId ||
            type(IHasAddressResolver).interfaceId == interfaceId ||
            type(ITextResolver).interfaceId == interfaceId ||
            type(IContentHashResolver).interfaceId == interfaceId ||
            type(IPubkeyResolver).interfaceId == interfaceId ||
            type(INameResolver).interfaceId == interfaceId ||
            type(IABIResolver).interfaceId == interfaceId ||
            type(IInterfaceResolver).interfaceId == interfaceId ||
            type(IERC7996).interfaceId == interfaceId ||
            type(UUPSUpgradeable).interfaceId == interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IERC7996
    function supportsFeature(bytes4 feature) public pure returns (bool) {
        return
            ResolverFeatures.RESOLVE_MULTICALL == feature || ResolverFeatures.SINGULAR == feature;
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /// @notice Initialize the contract.
    /// @param admin The resolver owner.
    /// @param roleBitmap The roles granted to `admin`.
    function initialize(address admin, uint256 roleBitmap) external initializer {
        if (admin == address(0)) {
            revert InvalidOwner();
        }
        _grantRoles(ROOT_RESOURCE, roleBitmap, admin, false);
    }

    /// @inheritdoc IDedicatedResolverSetters
    function setText(
        string calldata key,
        string calldata value
    )
        external
        onlyRoles(DedicatedResolverLib.textResource(key), DedicatedResolverLib.ROLE_SET_TEXT)
    {
        _storage().texts[key] = value;
        emit TextChanged(NODE_ANY, key, key, value);
    }

    /// @inheritdoc IDedicatedResolverSetters
    function setContenthash(
        bytes calldata hash
    ) external onlyRootRoles(DedicatedResolverLib.ROLE_SET_CONTENTHASH) {
        _storage().contenthash = hash;
        emit ContenthashChanged(NODE_ANY, hash);
    }

    /// @inheritdoc IDedicatedResolverSetters
    function setPubkey(
        bytes32 x,
        bytes32 y
    ) external onlyRootRoles(DedicatedResolverLib.ROLE_SET_PUBKEY) {
        _storage().pubkey = [x, y];
        emit PubkeyChanged(NODE_ANY, x, y);
    }

    /// @inheritdoc IDedicatedResolverSetters
    function setABI(
        uint256 contentType,
        bytes calldata data
    ) external onlyRootRoles(DedicatedResolverLib.ROLE_SET_ABI) {
        if (!_isPowerOf2(contentType)) {
            revert InvalidContentType(contentType);
        }
        _storage().abis[contentType] = data;
        emit ABIChanged(NODE_ANY, contentType);
    }

    /// @inheritdoc IDedicatedResolverSetters
    function setInterface(
        bytes4 interfaceId,
        address implementer
    ) external onlyRootRoles(DedicatedResolverLib.ROLE_SET_INTERFACE) {
        _storage().interfaces[interfaceId] = implementer;
        emit InterfaceChanged(NODE_ANY, interfaceId, implementer);
    }

    /// @inheritdoc IDedicatedResolverSetters
    function setName(
        string calldata name_
    ) external onlyRootRoles(DedicatedResolverLib.ROLE_SET_NAME) {
        _storage().name = name_;
        emit NameChanged(NODE_ANY, name_);
    }

    /// @inheritdoc IDedicatedResolverSetters
    function setAddr(
        uint256 coinType,
        bytes calldata addressBytes
    )
        external
        onlyRoles(DedicatedResolverLib.addrResource(coinType), DedicatedResolverLib.ROLE_SET_ADDR)
    {
        if (
            addressBytes.length != 0 && addressBytes.length != 20 && ENSIP19.isEVMCoinType(coinType)
        ) {
            revert InvalidEVMAddress(addressBytes);
        }
        _storage().addresses[coinType] = addressBytes;
        emit AddressChanged(NODE_ANY, coinType, addressBytes);
        if (coinType == COIN_TYPE_ETH) {
            emit AddrChanged(NODE_ANY, address(bytes20(addressBytes)));
        }
    }

    /// @notice Same as `multicall()`.
    /// @dev The purpose of node check is to prevent a trusted operator from modifying
    ///      multiple names.  Since the sole operator of this resolver is the owner and
    ///      it only stores records for a single name, the node check logic can be elided.
    ///
    ///      Additionally, the setters of this resolver do not have `node` as an argument.
    function multicallWithNodeCheck(
        bytes32,
        bytes[] calldata calls
    ) external returns (bytes[] memory) {
        return multicall(calls);
    }

    /// @notice Resolve records independent of name.
    /// @dev Reverts `UnsupportedResolverProfile` if the record is not supported.
    /// @param data The resolution data, as specified in ENSIP-10..
    /// @return The result of the resolution.
    function resolve(bytes calldata, bytes calldata data) external view returns (bytes memory) {
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

    /// @notice Get the text value for key.
    /// @param key The key.
    /// @return The text value.
    function text(bytes32, string calldata key) external view returns (string memory) {
        return _storage().texts[key];
    }

    /// @notice Get the content hash.
    /// @return The contenthash.
    function contenthash(bytes32) external view returns (bytes memory) {
        return _storage().contenthash;
    }

    /// @dev Get the public key.
    /// @return x The x coordinate of the public key.
    /// @return y The y coordinate of the public key.
    function pubkey(bytes32) external view returns (bytes32 x, bytes32 y) {
        DedicatedResolverLib.Storage storage $ = _storage();
        x = $.pubkey[0];
        y = $.pubkey[1];
    }

    /// @dev Get the first ABI for the specified content types.
    /// @param contentTypes Union of desired contents types.
    /// @return contentType The first matching content type (or 0 if no match).
    /// @return data The ABI data.
    // solhint-disable-next-line func-name-mixedcase
    function ABI(
        bytes32,
        uint256 contentTypes
    ) external view returns (uint256 contentType, bytes memory data) {
        DedicatedResolverLib.Storage storage $ = _storage();
        for (contentType = 1; contentType > 0 && contentType <= contentTypes; contentType <<= 1) {
            if ((contentType & contentTypes) != 0) {
                data = $.abis[contentType];
                if (data.length > 0) {
                    return (contentType, data);
                }
            }
        }
        return (0, "");
    }

    /// @dev Gets the implementer for an interface.
    /// @param interfaceId The interface ID.
    /// @return implementer The implementer address.
    function interfaceImplementer(
        bytes32,
        bytes4 interfaceId
    ) external view returns (address implementer) {
        implementer = _storage().interfaces[interfaceId];
        if (
            implementer == address(0) &&
            ERC165Checker.supportsInterface(addr(NODE_ANY), interfaceId)
        ) {
            implementer = address(this);
        }
    }

    /// @dev Get the primary name.
    /// @return The primary name.
    function name(bytes32) external view returns (string memory) {
        return _storage().name;
    }

    /// @inheritdoc IHasAddressResolver
    function hasAddr(bytes32, uint256 coinType) external view returns (bool) {
        return _storage().addresses[coinType].length > 0;
    }

    /// @notice Perform multiple read or write operations.
    /// @dev Reverts if any call fails.
    function multicall(bytes[] calldata calls) public returns (bytes[] memory results) {
        results = new bytes[](calls.length);
        for (uint256 i; i < calls.length; ++i) {
            (bool ok, bytes memory v) = address(this).delegatecall(calls[i]);
            if (!ok) {
                assembly {
                    revert(add(v, 32), v) // propagate the first error
                }
            }
            results[i] = v;
        }
        return results;
    }

    /// @notice Get the address for coin type.
    ///         If coin type is EVM and empty, defaults to `addr(COIN_TYPE_DEFAULT)`.
    /// @param coinType The coin type.
    /// @return addressBytes The address for the coin type.
    function addr(bytes32, uint256 coinType) public view returns (bytes memory addressBytes) {
        DedicatedResolverLib.Storage storage $ = _storage();
        addressBytes = $.addresses[coinType];
        if (addressBytes.length == 0 && ENSIP19.chainFromCoinType(coinType) > 0) {
            addressBytes = $.addresses[COIN_TYPE_DEFAULT];
        }
    }

    /// @notice Get `addr(60)` as `address`.
    /// @return The address for coin type 60.
    function addr(bytes32) public view returns (address payable) {
        return payable(address(bytes20(addr(NODE_ANY, COIN_TYPE_ETH))));
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    /// @dev Allow `ROLE_UPGRADE` to upgrade.
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRootRoles(DedicatedResolverLib.ROLE_UPGRADE) {
        //
    }

    function _msgSender()
        internal
        view
        virtual
        override(HCAContext, HCAContextUpgradeable)
        returns (address)
    {
        return HCAContextUpgradeable._msgSender();
    }

    function _msgData()
        internal
        view
        virtual
        override(Context, ContextUpgradeable)
        returns (bytes calldata)
    {
        return msg.data;
    }

    function _contextSuffixLength()
        internal
        view
        virtual
        override(Context, ContextUpgradeable)
        returns (uint256)
    {
        return 0;
    }

    /// @dev Returns true if `x` has a single bit set.
    function _isPowerOf2(uint256 x) internal pure returns (bool) {
        return x > 0 && (x - 1) & x == 0;
    }

    /// @dev Access storage pointer.
    function _storage() internal pure returns (DedicatedResolverLib.Storage storage layout) {
        uint256 slot = DedicatedResolverLib.NAMED_SLOT;
        assembly {
            layout.slot := slot
        }
    }
}
