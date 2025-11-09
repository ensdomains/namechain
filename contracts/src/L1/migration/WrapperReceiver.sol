// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/console.sol";

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {
    INameWrapper,
    IS_DOT_ETH,
    CAN_EXTEND_EXPIRY,
    PARENT_CANNOT_CONTROL,
    CANNOT_UNWRAP,
    CANNOT_BURN_FUSES,
    CANNOT_TRANSFER,
    CANNOT_SET_RESOLVER,
    CANNOT_SET_TTL,
    CANNOT_CREATE_SUBDOMAIN
} from "@ens/contracts/wrapper/INameWrapper.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {TransferData} from "../../common/bridge/types/TransferData.sol";
import {UnauthorizedCaller} from "../../common/CommonErrors.sol";
import {IRegistry} from "../../common/registry/interfaces/IRegistry.sol";
import {RegistryRolesLib} from "../../common/registry/libraries/RegistryRolesLib.sol";
import {WrappedErrorLib} from "../../common/utils/WrappedErrorLib.sol";
import {IWrapperRegistry, DATA_SIZE} from "../registry/interfaces/IWrapperRegistry.sol";

import {MigrationErrors} from "./MigrationErrors.sol";

uint32 constant FUSES_TO_BURN = CANNOT_BURN_FUSES |
    CANNOT_TRANSFER |
    CANNOT_SET_RESOLVER |
    CANNOT_SET_TTL |
    CANNOT_CREATE_SUBDOMAIN;

abstract contract WrapperReceiver is ERC165, IERC1155Receiver {
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    INameWrapper public immutable NAME_WRAPPER;
    VerifiableFactory public immutable VERIFIABLE_FACTORY;
    address public immutable MIGRATED_REGISTRY_IMPL;

    ////////////////////////////////////////////////////////////////////////
    // Modifiers
    ////////////////////////////////////////////////////////////////////////

    /// @dev Restrict `msg.sender` to `NAME_WRAPPER`.
    ///      Avoid `abi.decode()` failure for obviously invalid data.
    ///      Reverts wrapped errors for use inside of legacy IERC1155Receiver handler.
    modifier onlyWrapperDuringTransfer(bytes calldata data, uint256 expectedSize) {
        if (msg.sender != address(NAME_WRAPPER)) {
            WrappedErrorLib.wrapAndRevert(
                abi.encodeWithSelector(UnauthorizedCaller.selector, msg.sender)
            );
        }
        if (data.length != expectedSize) {
            WrappedErrorLib.wrapAndRevert(
                abi.encodeWithSelector(MigrationErrors.InvalidWrapperRegistryData.selector)
            );
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        INameWrapper nameWrapper,
        VerifiableFactory verifiableFactory,
        address migratedRegistryImpl
    ) {
        NAME_WRAPPER = nameWrapper;
        VERIFIABLE_FACTORY = verifiableFactory;
        MIGRATED_REGISTRY_IMPL = migratedRegistryImpl;
    }

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC1155Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    function onERC1155Received(
        address /*operator*/,
        address /*from*/,
        uint256 id,
        uint256 /*amount*/,
        bytes calldata data
    ) external onlyWrapperDuringTransfer(data, DATA_SIZE) returns (bytes4) {
        uint256[] memory ids = new uint256[](1);
        IWrapperRegistry.Data[] memory mds = new IWrapperRegistry.Data[](1);
        ids[0] = id;
        mds[0] = abi.decode(data, (IWrapperRegistry.Data)); // reverts empty if invalid
        try this.finishERC1155Migration(ids, mds) {
            return this.onERC1155Received.selector;
        } catch (bytes memory reason) {
            WrappedErrorLib.wrapAndRevert(reason); // convert all errors to wrapped
        }
    }

    function onERC1155BatchReceived(
        address /*operator*/,
        address /*from*/,
        uint256[] calldata ids,
        uint256[] calldata /*amounts*/,
        bytes calldata data
    ) external onlyWrapperDuringTransfer(data, 64 + ids.length * DATA_SIZE) returns (bytes4) {
        // never happens: caught by ERC1155Fuse
        // if (ids.length != amounts.length) {
        //     revert IERC1155Errors.ERC1155InvalidArrayLength(ids.length, amounts.length);
        // }
        IWrapperRegistry.Data[] memory mds = abi.decode(data, (IWrapperRegistry.Data[])); // reverts empty if invalid
        try this.finishERC1155Migration(ids, mds) {
            return this.onERC1155BatchReceived.selector;
        } catch (bytes memory reason) {
            WrappedErrorLib.wrapAndRevert(reason);
        }
    }

    function finishERC1155Migration(
        uint256[] calldata ids,
        IWrapperRegistry.Data[] calldata mds
    ) external {
        if (msg.sender != address(this)) {
            revert UnauthorizedCaller(msg.sender);
        }
        if (ids.length != mds.length) {
            revert IERC1155Errors.ERC1155InvalidArrayLength(ids.length, mds.length);
        }
        bytes32 parentNode = _parentNode();
        TransferData memory td;
        for (uint256 i; i < ids.length; ++i) {
            // never happens: caught by ERC1155Fuse
            // https://github.com/ensdomains/ens-contracts/blob/staging/contracts/wrapper/ERC1155Fuse.sol#L182
            // https://github.com/ensdomains/ens-contracts/blob/staging/contracts/wrapper/ERC1155Fuse.sol#L293
            // if (amounts[i] != 1) { ... }
            IWrapperRegistry.Data memory md = mds[i];
            if (md.owner == address(0)) {
                revert IERC1155Errors.ERC1155InvalidReceiver(address(0));
            }
            if (bytes32(ids[i]) != md.node) {
                revert MigrationErrors.TokenNodeMismatch(ids[i], md.node);
            }

            bytes memory name = NAME_WRAPPER.names(md.node); // exists
            string memory label = NameCoder.firstLabel(name); // exists
            bytes32 labelHash = keccak256(bytes(label));
            if (NameCoder.namehash(parentNode, labelHash) != md.node) {
                revert MigrationErrors.NameNotSubdomain(name, NAME_WRAPPER.names(parentNode));
            }

            (, uint32 fuses, uint64 expiry) = NAME_WRAPPER.getData(uint256(md.node));
            // ignore owner, only we can call this function => we own it

            if ((fuses & CANNOT_UNWRAP) == 0) {
                revert MigrationErrors.NameNotLocked(name);
            }
            if ((fuses & PARENT_CANNOT_CONTROL) == 0) {
                revert MigrationErrors.NameNotEmancipated(name);
            }

            // copy expiry
            if ((fuses & IS_DOT_ETH) != 0) {
                fuses &= ~CAN_EXTEND_EXPIRY; // 2LD is always renewable by anyone
                td.expiry = uint64(NAME_WRAPPER.registrar().nameExpires(uint256(labelHash))); // does not revert
            } else {
                td.expiry = expiry;
            }
            // NameWrapper subtracts GRACE_PERIOD from expiry during _beforeTransfer()
            // https://github.com/ensdomains/ens-contracts/blob/staging/contracts/wrapper/NameWrapper.sol#L822
            // expired names cannot be transferred:
            assert(td.expiry >= block.timestamp);
            // PermissionedRegistry._register() => CannotSetPastExpiration
            // wont happen as this operation is synchronous

            if ((fuses & CANNOT_SET_RESOLVER) != 0) {
                td.resolver = NAME_WRAPPER.ens().resolver(md.node); // copy V1 resolver
            } else {
                td.resolver = md.resolver; // accepts any value
                NAME_WRAPPER.setResolver(md.node, address(0)); // clear V1 resolver
            }

            (uint256 tokenRoles, uint256 subRegistryRoles) = _generateRoleBitmapsFromFuses(fuses);
            // PermissionedRegistry._register() => _grantRoles() => _checkRoleBitmap()
            // wont happen as roles are correct by construction

            // configure transfer
            td.label = label; // safe by construction
            td.owner = md.owner; // checked above
            td.roleBitmap = tokenRoles; // safe by construction

            // create subregistry
            td.subregistry = IRegistry(
                VERIFIABLE_FACTORY.deployProxy(
                    MIGRATED_REGISTRY_IMPL,
                    md.salt,
                    abi.encodeCall(
                        IWrapperRegistry.initialize,
                        (
                            IWrapperRegistry.ConstructorArgs({
                                node: md.node, // safe by construction
                                owner: md.owner, // safe by construction
                                ownerRoles: subRegistryRoles, // safe by construction
                                registrar: address(0) // TODO: md.registry?
                            })
                        )
                    )
                )
            );

            // add name to V2
            _inject(td);
            // PermissionedRegistry._register() => NameAlreadyRegistered
            // ERC1155._safeTransferFrom() => ERC1155InvalidReceiver

            // Burn all migration fuses
            NAME_WRAPPER.setFuses(md.node, uint16(FUSES_TO_BURN));
        }
    }

    function _inject(TransferData memory td) internal virtual returns (uint256 tokenId);

    function _parentNode() internal view virtual returns (bytes32);

    /// @notice Generates role bitmaps based on fuses
    /// @dev Returns two bitmaps: tokenRoles for the name registration and subRegistryRoles for the registry owner
    /// @param fuses The current fuses on the name
    /// @return tokenRoles The role bitmap for the owner on their name in their parent registry.
    /// @return subRegistryRoles The role bitmap for the owner on their name's subregistry.
    function _generateRoleBitmapsFromFuses(
        uint32 fuses
    ) internal pure returns (uint256 tokenRoles, uint256 subRegistryRoles) {
        // Check if fuses are permanently frozen
        bool fusesFrozen = (fuses & CANNOT_BURN_FUSES) != 0;

        tokenRoles |=
            RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER |
            RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER_ADMIN;

        // Include renewal permissions if expiry can be extended
        if ((fuses & CAN_EXTEND_EXPIRY) != 0) {
            tokenRoles |= RegistryRolesLib.ROLE_RENEW;
            if (!fusesFrozen) {
                tokenRoles |= RegistryRolesLib.ROLE_RENEW_ADMIN;
            }
        }

        // Conditionally add resolver roles
        if ((fuses & CANNOT_SET_RESOLVER) == 0) {
            tokenRoles |= RegistryRolesLib.ROLE_SET_RESOLVER;
            if (!fusesFrozen) {
                tokenRoles |= RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN;
            }
        }

        // Add transfer admin role if transfers are allowed
        if ((fuses & CANNOT_TRANSFER) == 0) {
            tokenRoles |= RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;
        }

        // Owner gets registrar permissions on subregistry only if subdomain creation is allowed
        if ((fuses & CANNOT_CREATE_SUBDOMAIN) == 0) {
            subRegistryRoles |= RegistryRolesLib.ROLE_REGISTRAR;
            if (!fusesFrozen) {
                subRegistryRoles |= RegistryRolesLib.ROLE_REGISTRAR_ADMIN;
            }
        }

        // Add renewal roles to subregistry
        subRegistryRoles |= RegistryRolesLib.ROLE_RENEW;
        subRegistryRoles |= RegistryRolesLib.ROLE_RENEW_ADMIN;
    }
}
