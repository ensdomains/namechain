// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {TransferData, MigrationData} from "../common/TransferData.sol";

import {IRegistry} from "../common/IRegistry.sol";
import {IRegistryDatastore} from "../common/IRegistryDatastore.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {IVerifiableFactory} from "../common/IVerifiableFactory.sol";
import {UserRegistry} from "./UserRegistry.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ITokenObserver} from "../common/ITokenObserver.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {EjectionController} from "../common/EjectionController.sol";
import {IBridge} from "../common/IBridge.sol";
import {BridgeEncoder} from "../common/BridgeEncoder.sol";
import {LibEACBaseRoles} from "../common/EnhancedAccessControl.sol";

/**
 * @title L2BridgeController
 * @dev Combined controller that handles both migration messages from L1 to L2 and ejection operations
 */
contract L2BridgeController is EjectionController, ITokenObserver {
    error MigrationFailed();
    error InvalidTLD(bytes32 labelHash);
    error NameAlreadyRegistered(bytes dnsEncodedName);
    error LabelNotFound(bytes dnsEncodedName, string label);
    error NotTokenOwner(uint256 tokenId);

    // Events
    event MigrationCompleted(bytes dnsEncodedName, uint256 newTokenId);

    bytes32 public constant ETH_TLD_HASH = keccak256(bytes("eth"));

    IPermissionedRegistry public immutable ethRegistry;
    IRegistryDatastore public immutable datastore;
    IVerifiableFactory public immutable verifiableFactory;
    address public immutable userRegistryImplementation;

    constructor(
        IBridge _bridge,
        IPermissionedRegistry _ethRegistry, 
        IRegistryDatastore _datastore,
        IVerifiableFactory _verifiableFactory,
        address _userRegistryImplementation
    ) EjectionController(_ethRegistry, _bridge) {
        ethRegistry = _ethRegistry;
        datastore = _datastore;
        verifiableFactory = _verifiableFactory;
        userRegistryImplementation = _userRegistryImplementation;
    }

    /**
     * @dev Complete migration from L1 to L2
     * Called by the bridge when a migration message is received from L1
     * 
     * @param dnsEncodedName The DNS encoded name being migrated
     * @param migrationData The migration data containing transfer details
     */
    function completeMigrationFromL1(
        bytes memory dnsEncodedName,
        MigrationData memory migrationData
    ) external onlyBridge {
        // Find the registry and validate the registry tree
        (IPermissionedRegistry targetRegistry, string memory label, bool exists) = _findAndValidateLabelStructure(dnsEncodedName, 0);

        if (exists) {
            revert NameAlreadyRegistered(dnsEncodedName);
        }

        // register the name - if toL1 is true, register to bridge controller, otherwise to final owner
        address initialOwner = migrationData.toL1 ? address(this) : migrationData.transferData.owner;
        
        // Create registry if not migrating to L1
        IPermissionedRegistry subregistry;
        if (!migrationData.toL1) {
            // Calculate salt based on block timestamp and migration data
            uint256 salt = uint256(keccak256(abi.encode(
                block.timestamp,
                migrationData.transferData.owner,
                migrationData.transferData.label,
                migrationData.transferData.expires
            )));
            
            // Encode the initialize call
            bytes memory initData = abi.encodeWithSelector(
                UserRegistry.initialize.selector,
                datastore,
                address(0), // metadata - will create SimpleRegistryMetadata
                LibEACBaseRoles.ALL_ROLES,
                migrationData.transferData.owner
            );
            
            // Deploy the user registry via verifiable factory
            address registryAddress = verifiableFactory.deployProxy(
                userRegistryImplementation,
                salt,
                initData
            );
            
            subregistry = IPermissionedRegistry(registryAddress);
        }
        
        uint256 tokenId = targetRegistry.register(
            label,
            initialOwner,
            migrationData.toL1 ? IPermissionedRegistry(address(0)) : subregistry,
            migrationData.transferData.resolver,
            migrationData.transferData.roleBitmap,
            migrationData.transferData.expires
        );

        // If migrating to L1, mark as ejected without sending bridge message
        if (migrationData.toL1) {
          // listen for events
          targetRegistry.setTokenObserver(tokenId, this);
        }

        emit MigrationCompleted(dnsEncodedName, tokenId);
    }

    /**
     * @dev Should be called when a name is being ejected back to L2.
     *
     * @param transferData The transfer data for the name being migrated
     */
    function completeEjectionFromL1(
        TransferData memory transferData
    ) 
    external 
    virtual 
    onlyBridge 
    {
        (uint256 tokenId,,) = registry.getNameData(transferData.label);

        if (registry.ownerOf(tokenId) != address(this)) {
            revert NotTokenOwner(tokenId);
        }

        registry.setSubregistry(tokenId, IRegistry(transferData.subregistry));
        registry.setResolver(tokenId, transferData.resolver);
        registry.safeTransferFrom(address(this), transferData.owner, tokenId, 1, "");

        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(transferData.label);
        emit NameEjectedToL2(dnsEncodedName, tokenId);
    }

    /**
     * @dev Override onERC1155Received to handle minting scenarios
     * When from is address(0), it's a mint operation and we should just return success
     * Otherwise, delegate to the parent implementation for ejection processing
     */
    function onERC1155Received(
        address /* operator */,
        address from,
        uint256 tokenId,
        uint256 /* amount */,
        bytes calldata data
    ) external virtual override returns (bytes4) {
        // If from is not address(0), it's not a mint operation - process as ejection
        if (from != address(0)) {
            _processEjection(tokenId, data);
        }
        
        return this.onERC1155Received.selector;
    }

    /**
     * @dev Default implementation of onRenew that does nothing.
     * Can be overridden in derived contracts for custom behavior.
     */
    function onRenew(uint256 /* tokenId */, uint64 /* expires */, address /* renewedBy */) external virtual {
        // Default implementation does nothing
    }

    /**
     * @dev Default implementation of onRelinquish that does nothing.
     * Can be overridden in derived contracts for custom behavior.
     */
    function onRelinquish(uint256 /* tokenId */, address /* relinquishedBy */) external virtual {
        // Default implementation does nothing
    }

    /**
     * @dev Recursively finds and validates the label registry structure
     * @param name The DNS-encoded name
     * @param offset The current offset in the name
     * @return registry The registry at this level
     * @return label The label at this level
     * @return exists True if the label at this level exists (only relevant for leftmost label)
     */
    function _findAndValidateLabelStructure(
        bytes memory name,
        uint256 offset
    ) internal view returns (IPermissionedRegistry registry, string memory label, bool exists) {
        uint256 size = uint8(name[offset]);
        
        // If we reach the end (size == 0), we should be at the root
        if (size == 0) {
            return (IPermissionedRegistry(address(0)), "", true);
        }
        
        // Check if this is the leftmost label (offset == 0)
        bool isLeftmostLabel = (offset == 0);
        
        // Recursively process the next part of the name (moving right to left)
        (IPermissionedRegistry parentRegistry,, ) = _findAndValidateLabelStructure(
            name,
            offset + 1 + size
        );
        
        // Read the current label
        (bytes32 labelHash, ) = NameCoder.readLabel(name, offset);
        
        // If we're at the rightmost position (parentRegistry is zero), this should be "eth"
        if (address(parentRegistry) == address(0)) {
            if (labelHash != ETH_TLD_HASH) {
                revert InvalidTLD(labelHash);
            }
            // Return the .eth registry
            return (ethRegistry, "", true);
        }
        
        label = NameUtils.readLabel(name, offset);

        // For non-TLD labels, check if they exist in the parent registry
        bool labelExists = address(parentRegistry.getSubregistry(label)) != address(0);
        
        // If this is the leftmost label (the one being migrated), return the result
        if (isLeftmostLabel) {
            if (labelExists) {
                return (parentRegistry, label, true);
            } else {
                return (parentRegistry, label, false);
            }
        }
        
        // For all other labels, they must exist
        if (!labelExists) {
            revert LabelNotFound(name, label);
        }
        
        // Return the subregistry of this label (where children should be registered)
        IPermissionedRegistry subregistry = IPermissionedRegistry(address(parentRegistry.getSubregistry(label)));
        return (subregistry, label, true);
    }

    /**
     * Overrides the EjectionController._onEject function.
     */
    function _onEject(uint256[] memory tokenIds, TransferData[] memory transferDataArray) internal virtual override {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            TransferData memory transferData = transferDataArray[i];

            // check that the label matches the token id
            _assertTokenIdMatchesLabel(tokenId, transferData.label);

            // NOTE: we don't nullify the resolver here, so that there is no resolution downtime
            registry.setSubregistry(tokenId, IRegistry(address(0)));

            // listen for events
            registry.setTokenObserver(tokenId, this);
            
            // Send bridge message for ejection
            bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(transferData.label);
            bridge.sendMessage(BridgeEncoder.encodeEjection(dnsEncodedName, transferData));
            emit NameEjectedToL1(dnsEncodedName, tokenId);
        }
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(EjectionController) returns (bool) {
        return interfaceId == type(ITokenObserver).interfaceId || super.supportsInterface(interfaceId);
    }
} 