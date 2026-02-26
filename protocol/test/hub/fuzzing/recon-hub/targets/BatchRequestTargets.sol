// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera deps
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";

// Utils
import {Helpers} from "../utils/Helpers.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";

/// @title BatchRequestTargets
/// @notice Target functions for the BatchRequestManager (977 lines, highest priority new contract).
///         Covers deposit/redeem request lifecycle: request → approve → issue/revoke → claim.
abstract contract BatchRequestTargets is BaseTargetFunctions, Properties {
    using CastLib for *;

    // ========================================================================
    // Deposit Flow
    // ========================================================================

    /// @dev Request deposit via BRM — auth-gated, called as admin
    function brm_requestDeposit(uint64 poolIdAsUint, bytes16 scIdAsBytes, uint128 amount) public updateGhostsWithType(OpType.DEPOSIT) {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = hubRegistry.currency(poolId);
        bytes32 investor = _getActor().toBytes32();

        try brm.requestDeposit(poolId, scId, amount, investor, assetId) {
            (, uint32 lastUpdate) = brm.depositRequest(poolId, scId, assetId, investor);
            uint32 nowDepositEpoch = brm.nowDepositEpoch(poolId, scId, assetId);

            // lastUpdate == nowDepositEpoch only when pending was directly mutated (not queued).
            // When user has unclaimed pending from a prior epoch, _updateQueued returns true
            // and lastUpdate stays at the old epoch. This is expected BRM behavior.
            lte(lastUpdate, nowDepositEpoch, "BRM: lastUpdate > nowDepositEpoch after requestDeposit");
        } catch (bytes memory reason) {
            uint128 pendingDeposit = brm.pendingDeposit(poolId, scId, assetId);
            if (uint256(pendingDeposit) + uint256(amount) < uint256(type(uint128).max)) {
                bool arithmeticRevert = checkError(reason, Panic.arithmeticPanic);
                t(!arithmeticRevert, "BRM: requestDeposit arithmetic panic (not overflow)");
            }
        }
    }

    function brm_requestDeposit_clamped(uint64 poolIdEntropy, uint32 scEntropy, uint128 amount) public {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);
        brm_requestDeposit(poolId.raw(), scId.raw(), amount);
    }

    /// @dev Cancel deposit request
    function brm_cancelDepositRequest(uint64 poolIdAsUint, bytes16 scIdAsBytes) public updateGhostsWithType(OpType.DEPOSIT) {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = hubRegistry.currency(poolId);
        bytes32 investor = _getActor().toBytes32();

        (uint128 pendingBefore,) = brm.depositRequest(poolId, scId, assetId, investor);

        try brm.cancelDepositRequest(poolId, scId, investor, assetId) returns (uint128) {
            (uint128 pendingAfter,) = brm.depositRequest(poolId, scId, assetId, investor);
            // After cancel, pending should decrease or be queued for cancellation
            lte(pendingAfter, pendingBefore, "BRM: pending increased after cancel deposit");
        } catch {}
    }

    function brm_cancelDepositRequest_clamped(uint64 poolIdEntropy, uint32 scEntropy) public {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);
        brm_cancelDepositRequest(poolId.raw(), scId.raw());
    }

    /// @dev Approve deposits — manager action
    function brm_approveDeposits(
        uint64 poolIdAsUint,
        bytes16 scIdAsBytes,
        uint32 nowDepositEpochId,
        uint128 approvedAssetAmount,
        uint128 pricePoolPerAsset
    ) public updateGhostsWithType(OpType.APPROVE_DEPOSITS) {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = hubRegistry.currency(poolId);

        try brm.approveDeposits(
            poolId, scId, assetId, nowDepositEpochId, approvedAssetAmount, D18.wrap(pricePoolPerAsset), address(0)
        ) {} catch {}
    }

    function brm_approveDeposits_clamped(uint64 poolIdEntropy, uint32 scEntropy, uint128 approvedAmount, uint128 price)
        public
    {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);
        uint32 nowEpoch = brm.nowDepositEpoch(poolId, scId, hubRegistry.currency(poolId));
        brm_approveDeposits(poolId.raw(), scId.raw(), nowEpoch, approvedAmount, price);
    }

    /// @dev Issue shares — manager action
    function brm_issueShares(
        uint64 poolIdAsUint,
        bytes16 scIdAsBytes,
        uint32 nowIssueEpochId,
        uint128 pricePoolPerShare
    ) public updateGhostsWithType(OpType.ISSUE_SHARES) {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = hubRegistry.currency(poolId);

        try brm.issueShares(poolId, scId, assetId, nowIssueEpochId, D18.wrap(pricePoolPerShare), 0, address(0)) {}
        catch {}
    }

    function brm_issueShares_clamped(uint64 poolIdEntropy, uint32 scEntropy, uint128 navPerShare) public {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);
        AssetId assetId = hubRegistry.currency(poolId);
        uint32 nowEpoch = brm.nowIssueEpoch(poolId, scId, assetId);
        brm_issueShares(poolId.raw(), scId.raw(), nowEpoch, navPerShare);
    }

    // ========================================================================
    // Redeem Flow
    // ========================================================================

    /// @dev Request redeem via BRM
    function brm_requestRedeem(uint64 poolIdAsUint, bytes16 scIdAsBytes, uint128 amount) public updateGhostsWithType(OpType.REDEEM) {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = hubRegistry.currency(poolId);
        bytes32 investor = _getActor().toBytes32();

        try brm.requestRedeem(poolId, scId, amount, investor, assetId) {
            (, uint32 lastUpdate) = brm.redeemRequest(poolId, scId, assetId, investor);
            uint32 nowRedeemEpoch = brm.nowRedeemEpoch(poolId, scId, assetId);

            // Same as deposit: lastUpdate stays at old epoch when request is queued
            lte(lastUpdate, nowRedeemEpoch, "BRM: lastUpdate > nowRedeemEpoch after requestRedeem");
        } catch {}
    }

    function brm_requestRedeem_clamped(uint64 poolIdEntropy, uint32 scEntropy, uint128 amount) public {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);
        brm_requestRedeem(poolId.raw(), scId.raw(), amount);
    }

    /// @dev Cancel redeem request
    function brm_cancelRedeemRequest(uint64 poolIdAsUint, bytes16 scIdAsBytes) public updateGhostsWithType(OpType.REDEEM) {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = hubRegistry.currency(poolId);
        bytes32 investor = _getActor().toBytes32();

        try brm.cancelRedeemRequest(poolId, scId, investor, assetId) {} catch {}
    }

    function brm_cancelRedeemRequest_clamped(uint64 poolIdEntropy, uint32 scEntropy) public {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);
        brm_cancelRedeemRequest(poolId.raw(), scId.raw());
    }

    /// @dev Approve redeems — manager action
    function brm_approveRedeems(
        uint64 poolIdAsUint,
        bytes16 scIdAsBytes,
        uint32 nowRedeemEpochId,
        uint128 approvedShareAmount,
        uint128 pricePoolPerAsset
    ) public updateGhostsWithType(OpType.APPROVE_REDEEMS) {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = hubRegistry.currency(poolId);

        try brm.approveRedeems(poolId, scId, assetId, nowRedeemEpochId, approvedShareAmount, D18.wrap(pricePoolPerAsset))
        {} catch {}
    }

    function brm_approveRedeems_clamped(uint64 poolIdEntropy, uint32 scEntropy, uint128 approvedAmount, uint128 price)
        public
    {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);
        AssetId assetId = hubRegistry.currency(poolId);
        uint32 nowEpoch = brm.nowRedeemEpoch(poolId, scId, assetId);
        brm_approveRedeems(poolId.raw(), scId.raw(), nowEpoch, approvedAmount, price);
    }

    /// @dev Revoke shares — manager action
    function brm_revokeShares(
        uint64 poolIdAsUint,
        bytes16 scIdAsBytes,
        uint32 nowRevokeEpochId,
        uint128 pricePoolPerShare
    ) public updateGhostsWithType(OpType.REVOKE_SHARES) {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = hubRegistry.currency(poolId);

        try brm.revokeShares(poolId, scId, assetId, nowRevokeEpochId, D18.wrap(pricePoolPerShare), 0, address(0)) {}
        catch {}
    }

    function brm_revokeShares_clamped(uint64 poolIdEntropy, uint32 scEntropy, uint128 navPerShare) public {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);
        AssetId assetId = hubRegistry.currency(poolId);
        uint32 nowEpoch = brm.nowRevokeEpoch(poolId, scId, assetId);
        brm_revokeShares(poolId.raw(), scId.raw(), nowEpoch, navPerShare);
    }

    // ========================================================================
    // Force Cancel
    // ========================================================================

    /// @dev Force cancel deposit — manager action, requires allowForceDepositCancel
    function brm_forceCancelDepositRequest(uint64 poolIdAsUint, bytes16 scIdAsBytes) public updateGhosts {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = hubRegistry.currency(poolId);
        bytes32 investor = _getActor().toBytes32();

        try brm.forceCancelDepositRequest(poolId, scId, investor, assetId, address(0)) {} catch {}
    }

    function brm_forceCancelDepositRequest_clamped(uint64 poolIdEntropy, uint32 scEntropy) public {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);
        brm_forceCancelDepositRequest(poolId.raw(), scId.raw());
    }

    /// @dev Force cancel redeem — manager action
    function brm_forceCancelRedeemRequest(uint64 poolIdAsUint, bytes16 scIdAsBytes) public updateGhosts {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = hubRegistry.currency(poolId);
        bytes32 investor = _getActor().toBytes32();

        try brm.forceCancelRedeemRequest(poolId, scId, investor, assetId, address(0)) {} catch {}
    }

    function brm_forceCancelRedeemRequest_clamped(uint64 poolIdEntropy, uint32 scEntropy) public {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);
        brm_forceCancelRedeemRequest(poolId.raw(), scId.raw());
    }
}
