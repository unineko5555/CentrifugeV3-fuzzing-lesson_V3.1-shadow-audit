// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera deps
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";

// Interfaces
import {IValuation} from "src/core/hub/interfaces/IValuation.sol";

// Utils
import {Helpers} from "../utils/Helpers.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";

/// @title NAVTargets
/// @notice Target functions for NAVManager — new v3.1 contract for accounting account management.
abstract contract NAVTargets is BaseTargetFunctions, Properties {
    // ========================================================================
    // NAV Initialization
    // ========================================================================

    function nav_initializeNetwork(uint64 poolIdAsUint, uint16 centrifugeId) public {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        try navManager.initializeNetwork(poolId, centrifugeId) {} catch {}
    }

    function nav_initializeHolding(uint64 poolIdAsUint, bytes16 scIdAsBytes, uint128 assetIdAsUint, bool isIdentity)
        public
    {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = AssetId.wrap(assetIdAsUint);
        IValuation valuation =
            isIdentity ? IValuation(address(identityValuation)) : IValuation(address(mockValuation));

        try navManager.initializeHolding(poolId, scId, assetId, valuation) {} catch {}
    }

    function nav_initializeHolding_clamped(uint64 poolIdEntropy, uint32 scEntropy, bool isIdentity) public {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);
        AssetId assetId = hubRegistry.currency(poolId);
        nav_initializeHolding(poolId.raw(), scId.raw(), assetId.raw(), isIdentity);
    }

    function nav_initializeLiability(uint64 poolIdAsUint, bytes16 scIdAsBytes, uint128 assetIdAsUint, bool isIdentity)
        public
    {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = AssetId.wrap(assetIdAsUint);
        IValuation valuation =
            isIdentity ? IValuation(address(identityValuation)) : IValuation(address(mockValuation));

        try navManager.initializeLiability(poolId, scId, assetId, valuation) {} catch {}
    }

    // ========================================================================
    // NAV Operations
    // ========================================================================

    function nav_updateHoldingValue(uint64 poolIdAsUint, bytes16 scIdAsBytes, uint128 assetIdAsUint)
        public
        updateGhostsWithType(OpType.UPDATE_NAV)
    {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = AssetId.wrap(assetIdAsUint);

        try navManager.updateHoldingValue(poolId, scId, assetId) {} catch {}
    }

    function nav_updateHoldingValue_clamped(uint64 poolIdEntropy, uint32 scEntropy) public {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);
        AssetId assetId = hubRegistry.currency(poolId);
        nav_updateHoldingValue(poolId.raw(), scId.raw(), assetId.raw());
    }

    function nav_closeGainLoss(uint64 poolIdAsUint, uint16 centrifugeId)
        public
        updateGhostsWithType(OpType.CLOSE_GAIN_LOSS)
    {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        try navManager.closeGainLoss(poolId, centrifugeId) {} catch {}
    }

    function nav_closeGainLoss_clamped(uint64 poolIdEntropy) public {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        nav_closeGainLoss(poolId.raw(), CENTRIFUGE_CHAIN_ID);
    }

    // ========================================================================
    // NAV View (for verification)
    // ========================================================================

    function nav_netAssetValue(uint64 poolIdAsUint, uint16 centrifugeId) public view returns (uint128) {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        return navManager.netAssetValue(poolId, centrifugeId);
    }
}
