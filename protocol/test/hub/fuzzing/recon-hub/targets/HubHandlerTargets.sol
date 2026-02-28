// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera deps
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId, newAssetId} from "src/core/types/AssetId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {D18, d18} from "src/misc/types/D18.sol";

// Interfaces
import {IHubRequestManager} from "src/core/hub/interfaces/IHubRequestManager.sol";

// Utils
import {Helpers} from "../utils/Helpers.sol";
import {BeforeAfter} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";

/// @title HubHandlerTargets
/// @notice Target functions for HubHandler — gateway callback simulation.
///         Unlocks Holdings increase/decrease, Hub._updateAccountingAmount, ShareClassManager.updateShares.
abstract contract HubHandlerTargets is BaseTargetFunctions, Properties {
    // ========================================================================
    // updateHoldingAmount — main holding value function
    // ========================================================================

    function hubHandler_updateHoldingAmount(
        uint16 centrifugeId,
        uint64 poolIdAsUint,
        bytes16 scIdAsBytes,
        uint128 assetIdAsUint,
        uint128 amount,
        uint128 priceRaw,
        bool isIncrease,
        bool isSnapshot,
        uint64 nonce
    ) public updateGhosts {
        hubHandler.updateHoldingAmount(
            centrifugeId,
            PoolId.wrap(poolIdAsUint),
            ShareClassId.wrap(scIdAsBytes),
            AssetId.wrap(assetIdAsUint),
            amount,
            D18.wrap(priceRaw),
            isIncrease,
            isSnapshot,
            nonce
        );
    }

    function hubHandler_updateHoldingAmount_clamped(
        uint64 poolIdEntropy,
        uint32 scEntropy,
        uint128 amount,
        uint128 priceRaw,
        bool isIncrease
    ) public updateGhosts {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);
        AssetId assetId = hubRegistry.currency(poolId);

        // Clamp price to reasonable range [0.01, 100] in D18
        priceRaw = uint128(uint256(priceRaw) % 100e18) + 1e16;
        // Clamp amount to avoid overflow
        amount = uint128(uint256(amount) % uint256(type(uint64).max)) + 1;

        try hubHandler.updateHoldingAmount(
            CENTRIFUGE_CHAIN_ID,
            poolId,
            scId,
            assetId,
            amount,
            D18.wrap(priceRaw),
            isIncrease,
            IS_SNAPSHOT,
            NONCE
        ) {} catch {}
    }

    // ========================================================================
    // updateShares — share issuance/revocation via gateway
    // ========================================================================

    function hubHandler_updateShares(
        uint16 centrifugeId,
        uint64 poolIdAsUint,
        bytes16 scIdAsBytes,
        uint128 amount,
        bool isIssuance,
        bool isSnapshot,
        uint64 nonce
    ) public updateGhosts {
        hubHandler.updateShares(
            centrifugeId,
            PoolId.wrap(poolIdAsUint),
            ShareClassId.wrap(scIdAsBytes),
            amount,
            isIssuance,
            isSnapshot,
            nonce
        );
    }

    function hubHandler_updateShares_clamped(
        uint64 poolIdEntropy,
        uint32 scEntropy,
        uint128 amount,
        bool isIssuance
    ) public updateGhosts {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);

        amount = uint128(uint256(amount) % uint256(type(uint64).max)) + 1;

        try hubHandler.updateShares(
            CENTRIFUGE_CHAIN_ID, poolId, scId, amount, isIssuance, IS_SNAPSHOT, NONCE
        ) {} catch {}
    }

    // ========================================================================
    // request — forward request to HubRequestManager
    // ========================================================================

    function hubHandler_request(uint64 poolIdAsUint, bytes16 scIdAsBytes, uint128 assetIdAsUint, bytes calldata payload)
        public
        updateGhosts
    {
        hubHandler.request(
            PoolId.wrap(poolIdAsUint), ShareClassId.wrap(scIdAsBytes), AssetId.wrap(assetIdAsUint), payload
        );
    }

    function hubHandler_request_clamped(uint64 poolIdEntropy, uint32 scEntropy) public updateGhosts {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);
        AssetId assetId = hubRegistry.currency(poolId);

        // Minimal empty payload — request manager handles parsing
        try hubHandler.request(poolId, scId, assetId, "") {} catch {}
    }

    // ========================================================================
    // registerAsset — asset registration via gateway
    // ========================================================================

    function hubHandler_registerAsset(uint128 assetIdAsUint, uint8 decimals) public updateGhosts {
        hubHandler.registerAsset(AssetId.wrap(assetIdAsUint), decimals);
    }
}
