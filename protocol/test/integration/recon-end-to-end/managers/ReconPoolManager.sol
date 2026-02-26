// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {MockERC20} from "@recon/MockERC20.sol";
import {vm} from "@chimera/Hevm.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId, newAssetId} from "src/core/types/AssetId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";

// Interfaces
import {IValuation} from "src/core/hub/interfaces/IValuation.sol";
import {IVault} from "src/core/spoke/interfaces/IVault.sol";
import {IVaultFactory} from "src/core/spoke/factories/interfaces/IVaultFactory.sol";
import {IRequestManager} from "src/core/interfaces/IRequestManager.sol";
import {VaultUpdateKind} from "src/core/messaging/libraries/MessageLib.sol";

// Hooks
import {UpdateRestrictionMessageLib} from "src/hooks/libraries/UpdateRestrictionMessageLib.sol";

// Contracts
import {AsyncVault} from "src/vaults/AsyncVault.sol";
import {ShareToken} from "src/core/spoke/ShareToken.sol";

// Parent
import {Setup} from "../Setup.sol";

/// @title ReconPoolManager
/// @notice Helper that wraps the complex multi-step pool+vault creation flow.
///         In E2E mode, hub operations automatically send cross-chain messages to the spoke
///         via the real Gateway/LocalAdapter stack, so we only need to call Hub-side functions.
///
///         IMPORTANT: Account creation is delegated to NAVManager (not manual hub.createAccount)
///         to ensure account IDs match the production system (withCentrifugeId/withAssetId encoding).
abstract contract ReconPoolManager is Setup {
    using CastLib for *;

    /// @dev Create a full pool+shareClass+holding+vault from scratch.
    ///      This is the E2E equivalent of the recon-core GatewayMockTargets.deployNewTokenPoolAndShare().
    ///
    /// Flow:
    ///   1. Deploy MockERC20 asset
    ///   2. Register asset on hub (hubRegistry.registerAsset)
    ///   3. Create pool on hub (hub.createPool) — admin = address(this)
    ///   4. Wire NAVManager + OracleValuation as hub managers for this pool
    ///   5. Add share class (hub.addShareClass)
    ///   6. Initialize NAV network + holding via NAVManager (creates proper account IDs)
    ///   7. notifyPool → message → spoke.addPool (automatic via LocalAdapter)
    ///   8. notifyShareClass → message → spoke.addShareClass (with hook=fullRestrictions)
    ///   9. setRequestManager (brm → asyncRequestManager) → message → spoke
    ///  10. updateBalanceSheetManager (ARM, test contract, QueueManager) → message → spoke
    ///  11. updateVault (DeployAndLink) → message → spoke: deploy + link vault
    ///  12. updateRestriction: add actors as members on spoke
    ///  13. Mint tokens to actors
    function createPoolAndSetup(uint8 decimals, uint128 initialMintPerActor)
        internal
        returns (PoolId poolId, ShareClassId scId, AssetId assetId, address vaultAddr)
    {
        // -----------------------------------------------------------------
        // 1. Deploy asset
        // -----------------------------------------------------------------
        MockERC20 asset = new MockERC20("Test Asset", "TASSET", decimals);
        defaultAsset = asset;

        // -----------------------------------------------------------------
        // 2. Register asset on hub
        // -----------------------------------------------------------------
        assetId = newAssetId(SPOKE_CENTRIFUGE_ID, ASSET_ID_COUNTER);
        ASSET_ID_COUNTER++;
        hubRegistry.registerAsset(assetId, decimals);

        // Register asset on spoke (first param = HUB centrifugeId = message target)
        spoke.registerAsset{value: 0}(HUB_CENTRIFUGE_ID, address(asset), 0, address(this));

        // Track asset mapping
        uint128 rawId = AssetId.unwrap(assetId);
        assetAddressToAssetId[address(asset)] = rawId;
        assetIdToAssetAddress[rawId] = address(asset);

        // -----------------------------------------------------------------
        // 3. Create pool
        // -----------------------------------------------------------------
        uint64 poolIdRaw = (uint64(HUB_CENTRIFUGE_ID) << 48) | uint64(POOL_ID_COUNTER);
        POOL_ID_COUNTER++;
        poolId = PoolId.wrap(poolIdRaw);
        hub.createPool(poolId, address(this), assetId);
        createdPools.push(poolId);
        poolCurrency[poolId] = assetId;
        poolCreated = true;

        // -----------------------------------------------------------------
        // 4. Wire NAVManager + OracleValuation as hub managers for this pool
        //    (required so NAVManager can call hub.createAccount, hub.initializeHolding, etc.)
        //    address(this) is already a hub manager from createPool.
        // -----------------------------------------------------------------
        hub.updateHubManager(poolId, address(navManager), true);
        hub.updateHubManager(poolId, address(oracleValuation), true);

        // Set this contract as NAVManager's manager (so we can call initializeNetwork, etc.)
        navManager.updateManager(poolId, address(this), true);

        // Set this contract as OracleValuation's feeder (so we can call setPrice)
        oracleValuation.updateFeeder(poolId, address(this), true);

        // -----------------------------------------------------------------
        // 5. Add share class
        // -----------------------------------------------------------------
        scId = hub.addShareClass(poolId, "E2E Share", "E2ESH", bytes32(uint256(1)));
        poolShareClasses[poolId].push(scId);

        // -----------------------------------------------------------------
        // 6. Initialize NAV: network + holding via NAVManager
        //    NAVManager.initializeNetwork creates equity/liability/gain/loss accounts
        //    NAVManager.initializeHolding creates asset account + calls hub.initializeHolding
        //    Account IDs use withCentrifugeId/withAssetId encoding (production scheme)
        // -----------------------------------------------------------------
        navManager.initializeNetwork(poolId, SPOKE_CENTRIFUGE_ID);
        navManager.initializeHolding(poolId, scId, assetId, IValuation(address(identityValuation)));

        // -----------------------------------------------------------------
        // 7. Notify pool → spoke (cross-chain via real messaging)
        // -----------------------------------------------------------------
        hub.notifyPool(poolId, SPOKE_CENTRIFUGE_ID, address(this));

        // -----------------------------------------------------------------
        // 8. Notify share class → spoke (with FullRestrictions hook)
        // -----------------------------------------------------------------
        hub.notifyShareClass(
            poolId, scId, SPOKE_CENTRIFUGE_ID,
            CastLib.toBytes32(address(fullRestrictions)),
            address(this)
        );

        // Get the token created on spoke
        token = ShareToken(address(spoke.shareToken(poolId, scId)));
        shareClassTokens.push(address(token));

        // -----------------------------------------------------------------
        // 9. Set request manager (BRM on hub, ARM on spoke)
        // -----------------------------------------------------------------
        hub.setRequestManager(
            poolId, SPOKE_CENTRIFUGE_ID,
            brm,
            CastLib.toBytes32(address(asyncRequestManager)),
            address(this)
        );

        // -----------------------------------------------------------------
        // 10. Update balance sheet managers
        //     ARM: for deposit/redeem fulfillment (via cross-chain message)
        //     Test contract: for direct bs_submitQueued* and other BalanceSheet targets
        //     QueueManager: for sync operations
        // -----------------------------------------------------------------
        hub.updateBalanceSheetManager(
            poolId, SPOKE_CENTRIFUGE_ID,
            CastLib.toBytes32(address(asyncRequestManager)),
            true,
            address(this)
        );
        balanceSheet.updateManager(poolId, address(this), true);
        balanceSheet.updateManager(poolId, address(queueManager), true);

        // -----------------------------------------------------------------
        // 11. Deploy and link vault via cross-chain message
        // -----------------------------------------------------------------
        hub.updateVault(
            poolId, scId, assetId,
            CastLib.toBytes32(address(vaultFactory)),
            VaultUpdateKind.DeployAndLink,
            0,
            address(this)
        );

        // Get vault address from spoke's VaultRegistry
        vaultAddr = address(vaultRegistry.vault(poolId, scId, assetId, IRequestManager(address(asyncRequestManager))));
        vault = AsyncVault(vaultAddr);
        vaultAddresses.push(vaultAddr);
        vaultDeployed = true;

        // -----------------------------------------------------------------
        // 12. Update restriction: add actors as members
        // -----------------------------------------------------------------
        _addActorsAsMembers(poolId, scId);

        // -----------------------------------------------------------------
        // 13. Mint tokens to actors
        // -----------------------------------------------------------------
        _mintToActors(asset, initialMintPerActor, vaultAddr);

        // Set active IDs
        activePoolId = poolId;
        activeScId = scId;
        activeAssetId = assetId;
    }

    /// @dev Add all actors as members on the share class (via Hub cross-chain restriction update)
    function _addActorsAsMembers(PoolId poolId, ShareClassId scId) internal {
        address[] memory actors = _getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            bytes memory payload = UpdateRestrictionMessageLib.serialize(
                UpdateRestrictionMessageLib.UpdateRestrictionMember({
                    user: CastLib.toBytes32(actors[i]),
                    validUntil: type(uint64).max
                })
            );
            hub.updateRestriction(poolId, scId, SPOKE_CENTRIFUGE_ID, payload, 0, address(this));
        }
        // Also add the test contract itself as member
        bytes memory selfPayload = UpdateRestrictionMessageLib.serialize(
            UpdateRestrictionMessageLib.UpdateRestrictionMember({
                user: CastLib.toBytes32(address(this)),
                validUntil: type(uint64).max
            })
        );
        hub.updateRestriction(poolId, scId, SPOKE_CENTRIFUGE_ID, selfPayload, 0, address(this));
    }

    /// @dev Mint test tokens to all actors and approve vault + escrow
    function _mintToActors(MockERC20 asset, uint128 amountPerActor, address) internal {
        address[] memory actors = _getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            asset.mint(actors[i], uint256(amountPerActor));
            vm.prank(actors[i]);
            asset.approve(address(vault), type(uint256).max);
            vm.prank(actors[i]);
            asset.approve(address(escrow), type(uint256).max);
        }
        // Also mint to test contract for direct BRM operations
        asset.mint(address(this), uint256(amountPerActor));
        asset.approve(address(vault), type(uint256).max);
        asset.approve(address(escrow), type(uint256).max);
    }

    /// @dev Add a new share class to an existing pool, with full spoke notification.
    ///      Uses NAVManager for holding initialization (same encoding as production).
    function addShareClassToPool(PoolId poolId, string memory name, string memory symbol, bytes32 salt)
        internal
        returns (ShareClassId scId)
    {
        scId = hub.addShareClass(poolId, name, symbol, salt);
        poolShareClasses[poolId].push(scId);

        // Initialize holding via NAVManager (network already initialized for this pool)
        AssetId assetId = poolCurrency[poolId];
        navManager.initializeHolding(poolId, scId, assetId, IValuation(address(identityValuation)));

        // Notify spoke
        hub.notifyShareClass(
            poolId, scId, SPOKE_CENTRIFUGE_ID,
            CastLib.toBytes32(address(fullRestrictions)),
            address(this)
        );

        // Add actors as members
        _addActorsAsMembers(poolId, scId);

        // Track share class token
        ShareToken scToken = ShareToken(address(spoke.shareToken(poolId, scId)));
        shareClassTokens.push(address(scToken));
    }
}
