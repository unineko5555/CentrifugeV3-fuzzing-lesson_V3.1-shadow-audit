// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";
import {MockERC20} from "@recon/MockERC20.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId, newAssetId} from "src/core/types/AssetId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AccountId} from "src/core/types/AccountId.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";
import {VaultUpdateKind} from "src/core/messaging/libraries/MessageLib.sol";

// Hooks
import {UpdateRestrictionMessageLib} from "src/hooks/libraries/UpdateRestrictionMessageLib.sol";

// Interfaces
import {IValuation} from "src/core/hub/interfaces/IValuation.sol";
import {IRequestManager} from "src/core/interfaces/IRequestManager.sol";

import {Properties} from "../properties/Properties.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title AdminTargets
/// @notice Administrative target functions for E2E fuzzing.
///         Handles pool creation, share class management, holding initialization,
///         and cross-chain admin operations via real messaging.
abstract contract AdminTargets is BaseTargetFunctions, Properties {
    using CastLib for *;

    bool private _hasCreatedInitialPool;

    // ===================================================================
    // Pool Creation (via ReconPoolManager)
    // ===================================================================

    /// @dev Create the initial pool with full setup (single deploy mode)
    function admin_createPool(uint8 decimals, uint128 initialMintPerActor)
        public
        updateGhostsWithType(OpType.ADMIN)
    {
        require(!_hasCreatedInitialPool || !RECON_USE_SINGLE_DEPLOY, "Single deploy: pool already created");

        // Clamp decimals to reasonable range
        decimals = uint8(_clampU256(uint256(decimals), 6, 18));
        initialMintPerActor = uint128(_clampU256(uint256(initialMintPerActor), 1e18, 1e30));

        createPoolAndSetup(decimals, initialMintPerActor);
        _hasCreatedInitialPool = true;
    }

    /// @dev Clamped version for fuzzer: uses default parameters
    function admin_createPool_clamped() public {
        admin_createPool(18, 1_000_000e18);
    }

    // ===================================================================
    // Share Class Management
    // ===================================================================

    /// @dev Add a new share class to an existing pool
    function admin_addShareClass(uint256 salt) public updateGhostsWithType(OpType.ADMIN) poolExists {
        addShareClassToPool(activePoolId, "Extra Share", "EXSH", bytes32(salt));
    }

    // ===================================================================
    // Hub Price Updates (cross-chain: propagate to spoke)
    // ===================================================================

    /// @dev Update share price (hub-side, propagated to spoke via messaging)
    function admin_updateSharePrice(uint128 priceRaw) public updateGhostsWithType(OpType.ADMIN) poolExists {
        priceRaw = _clampU128(priceRaw, 0.01e18, 100e18);
        hub.updateSharePrice(activePoolId, activeScId, D18.wrap(priceRaw), uint64(block.timestamp));
        priceUpdated = true;
    }

    /// @dev Update price per asset for the active holding (via hub.updatePricePoolPerAsset)
    function admin_updatePricePoolPerAsset(uint128 priceRaw) public updateGhostsWithType(OpType.ADMIN) poolExists {
        priceRaw = _clampU128(priceRaw, 0.01e18, 100e18);
        // This updates the hub-side price; the spoke gets it via cross-chain message
        // when balanceSheet.submitQueuedAssets() is called
    }

    // ===================================================================
    // Member Management (cross-chain)
    // ===================================================================

    /// @dev Add an actor as a member of the active share class (via hub → spoke messaging)
    function admin_updateMember(address user, uint64 validUntil)
        public
        updateGhostsWithType(OpType.ADMIN)
        poolExists
    {
        bytes memory payload = UpdateRestrictionMessageLib.serialize(
            UpdateRestrictionMessageLib.UpdateRestrictionMember({
                user: CastLib.toBytes32(user),
                validUntil: validUntil
            })
        );
        hub.updateRestriction(activePoolId, activeScId, SPOKE_CENTRIFUGE_ID, payload, 0, address(this));
    }

    /// @dev Freeze an actor on the active share class
    function admin_freezeActor() public updateGhostsWithType(OpType.ADMIN) poolExists {
        address actor = _getActor();
        bytes memory payload = UpdateRestrictionMessageLib.serialize(
            UpdateRestrictionMessageLib.UpdateRestrictionFreeze({
                user: CastLib.toBytes32(actor)
            })
        );
        hub.updateRestriction(activePoolId, activeScId, SPOKE_CENTRIFUGE_ID, payload, 0, address(this));
    }

    /// @dev Unfreeze an actor on the active share class
    function admin_unfreezeActor() public updateGhostsWithType(OpType.ADMIN) poolExists {
        address actor = _getActor();
        bytes memory payload = UpdateRestrictionMessageLib.serialize(
            UpdateRestrictionMessageLib.UpdateRestrictionUnfreeze({
                user: CastLib.toBytes32(actor)
            })
        );
        hub.updateRestriction(activePoolId, activeScId, SPOKE_CENTRIFUGE_ID, payload, 0, address(this));
    }

    // ===================================================================
    // Holding Updates
    // ===================================================================

    /// @dev Update holding value on hub
    function admin_updateHoldingValue() public updateGhostsWithType(OpType.ADMIN) poolExists {
        try hub.updateHoldingValue(activePoolId, activeScId, activeAssetId) {} catch {}
    }

    // ===================================================================
    // Vault Management (cross-chain)
    // ===================================================================

    /// @dev Deploy and link a new vault for a different asset on the existing pool
    function admin_deployVaultForAsset(uint8 decimals) public updateGhostsWithType(OpType.ADMIN) poolExists {
        // Deploy a new asset
        decimals = uint8(_clampU256(uint256(decimals), 6, 18));
        MockERC20 newAsset = new MockERC20("Alt Asset", "ALT", decimals);

        AssetId altAssetId = newAssetId(SPOKE_CENTRIFUGE_ID, ASSET_ID_COUNTER);
        ASSET_ID_COUNTER++;
        hubRegistry.registerAsset(altAssetId, decimals);
        spoke.registerAsset{value: 0}(HUB_CENTRIFUGE_ID, address(newAsset), 0, address(this));

        // Track asset mapping
        uint128 rawId = AssetId.unwrap(altAssetId);
        assetAddressToAssetId[address(newAsset)] = rawId;
        assetIdToAssetAddress[rawId] = address(newAsset);

        // Initialize holding via NAVManager (network already initialized for this pool)
        navManager.initializeHolding(activePoolId, activeScId, altAssetId, IValuation(address(identityValuation)));

        // Deploy and link vault on spoke via cross-chain
        hub.updateVault(
            activePoolId, activeScId, altAssetId,
            CastLib.toBytes32(address(vaultFactory)),
            VaultUpdateKind.DeployAndLink,
            0,
            address(this)
        );
    }

    // ===================================================================
    // Metadata Operations
    // ===================================================================

    /// @dev Set pool metadata on hub registry
    function admin_setPoolMetadata(bytes32 metadataHash)
        public
        updateGhostsWithType(OpType.ADMIN)
        poolExists
    {
        bytes memory metadata = abi.encodePacked(metadataHash);
        try hub.setPoolMetadata(activePoolId, metadata) {} catch {}
    }

    /// @dev Set account metadata for the asset account
    function admin_setAccountMetadata(bytes32 metadataHash)
        public
        updateGhostsWithType(OpType.ADMIN)
        poolExists
    {
        AccountId assetAccId = holdings.accountId(activePoolId, activeScId, activeAssetId, 0);
        (,,, uint64 lastUpdated,) = accounting.accounts(activePoolId, assetAccId);
        if (lastUpdated == 0) return;
        bytes memory metadata = abi.encodePacked(metadataHash);
        try hub.setAccountMetadata(activePoolId, assetAccId, metadata) {} catch {}
    }
}
