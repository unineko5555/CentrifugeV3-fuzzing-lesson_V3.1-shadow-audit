// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {Panic} from "@recon/Panic.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";

import {Properties} from "../properties/Properties.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title BatchRequestTargets
/// @notice Hub-side BRM operations for E2E fuzzing.
///         In E2E mode, issueShares/revokeShares automatically trigger cross-chain
///         messages to the spoke via real Gateway/LocalAdapter stack.
///         Covers: request → approve → issue/revoke → notify → claim lifecycle.
abstract contract BatchRequestTargets is BaseTargetFunctions, Properties {
    using CastLib for *;

    // ===================================================================
    // Deposit Flow
    // ===================================================================

    /// @dev Request deposit via BRM (Hub-side direct)
    function brm_requestDeposit(uint128 amount) public updateGhostsWithType(OpType.BRM_REQUEST_DEPOSIT) poolExists {
        amount = _clampAmount(amount);
        bytes32 investor = CastLib.toBytes32(_getActor());

        try brm.requestDeposit(activePoolId, activeScId, amount, investor, activeAssetId) {
            // Update ghost
            ghostPendingDeposit[activePoolId][activeScId][activeAssetId] += amount;
        } catch {}
    }

    /// @dev Cancel deposit request
    function brm_cancelDepositRequest()
        public
        updateGhostsWithType(OpType.BRM_CANCEL_DEPOSIT)
        poolExists
    {
        bytes32 investor = CastLib.toBytes32(_getActor());
        (uint128 pendingBefore,) = brm.depositRequest(activePoolId, activeScId, activeAssetId, investor);

        try brm.cancelDepositRequest(activePoolId, activeScId, investor, activeAssetId) returns (uint128) {
            cancelExecuted = true;
        } catch {}
    }

    /// @dev Approve deposits — manager action
    function brm_approveDeposits(uint128 approvedAmount, uint128 priceRaw)
        public
        updateGhostsWithType(OpType.BRM_APPROVE_DEPOSITS)
        poolExists
    {
        approvedAmount = _clampAmount(approvedAmount);
        priceRaw = _clampU128(priceRaw, 0.01e18, 100e18);

        uint32 nowEpoch = brm.nowDepositEpoch(activePoolId, activeScId, activeAssetId);

        try brm.approveDeposits(
            activePoolId, activeScId, activeAssetId,
            nowEpoch, approvedAmount, D18.wrap(priceRaw), address(this)
        ) {} catch {}
    }

    /// @dev Issue shares — manager action (triggers cross-chain message to spoke)
    function brm_issueShares(uint128 priceRaw)
        public
        updateGhostsWithType(OpType.BRM_ISSUE_SHARES)
        poolExists
    {
        priceRaw = _clampU128(priceRaw, 0.01e18, 100e18);

        uint32 nowEpoch = brm.nowIssueEpoch(activePoolId, activeScId, activeAssetId);

        try brm.issueShares(
            activePoolId, activeScId, activeAssetId,
            nowEpoch, D18.wrap(priceRaw), 0, address(this)
        ) {} catch {}
    }

    // ===================================================================
    // Redeem Flow
    // ===================================================================

    /// @dev Request redeem via BRM (Hub-side direct)
    function brm_requestRedeem(uint128 amount) public updateGhostsWithType(OpType.BRM_REQUEST_REDEEM) poolExists {
        amount = _clampAmount(amount);
        bytes32 investor = CastLib.toBytes32(_getActor());

        try brm.requestRedeem(activePoolId, activeScId, amount, investor, activeAssetId) {
            // Update ghost
            ghostPendingRedeem[activePoolId][activeScId][activeAssetId] += amount;
        } catch {}
    }

    /// @dev Cancel redeem request
    function brm_cancelRedeemRequest()
        public
        updateGhostsWithType(OpType.BRM_CANCEL_REDEEM)
        poolExists
    {
        bytes32 investor = CastLib.toBytes32(_getActor());
        try brm.cancelRedeemRequest(activePoolId, activeScId, investor, activeAssetId) {}
        catch {}
    }

    /// @dev Approve redeems — manager action
    function brm_approveRedeems(uint128 approvedAmount, uint128 priceRaw)
        public
        updateGhostsWithType(OpType.BRM_APPROVE_REDEEMS)
        poolExists
    {
        approvedAmount = _clampAmount(approvedAmount);
        priceRaw = _clampU128(priceRaw, 0.01e18, 100e18);

        uint32 nowEpoch = brm.nowRedeemEpoch(activePoolId, activeScId, activeAssetId);

        try brm.approveRedeems(
            activePoolId, activeScId, activeAssetId,
            nowEpoch, approvedAmount, D18.wrap(priceRaw)
        ) {} catch {}
    }

    /// @dev Revoke shares — manager action (triggers cross-chain message to spoke)
    function brm_revokeShares(uint128 priceRaw)
        public
        updateGhostsWithType(OpType.BRM_REVOKE_SHARES)
        poolExists
    {
        priceRaw = _clampU128(priceRaw, 0.01e18, 100e18);

        uint32 nowEpoch = brm.nowRevokeEpoch(activePoolId, activeScId, activeAssetId);

        try brm.revokeShares(
            activePoolId, activeScId, activeAssetId,
            nowEpoch, D18.wrap(priceRaw), 0, address(this)
        ) {} catch {}
    }

    // ===================================================================
    // Force Cancel
    // ===================================================================

    /// @dev Force cancel deposit request
    function brm_forceCancelDepositRequest() public updateGhosts poolExists {
        bytes32 investor = CastLib.toBytes32(_getActor());
        try brm.forceCancelDepositRequest(activePoolId, activeScId, investor, activeAssetId, address(this)) {}
        catch {}
    }

    /// @dev Force cancel redeem request
    function brm_forceCancelRedeemRequest() public updateGhosts poolExists {
        bytes32 investor = CastLib.toBytes32(_getActor());
        try brm.forceCancelRedeemRequest(activePoolId, activeScId, investor, activeAssetId, address(this)) {}
        catch {}
    }

    // ===================================================================
    // Shortcuts (full cycle in one call)
    // ===================================================================

    /// @dev Full deposit cycle: request → approve → issue → notify
    function shortcut_deposit_approve_issue(uint128 amount, uint128 priceRaw) public poolExists {
        amount = _clampAmount(amount);
        priceRaw = _clampU128(priceRaw, 0.01e18, 100e18);
        D18 price = D18.wrap(priceRaw);

        _shortcutFullDeposit(
            activePoolId, activeScId, activeAssetId,
            CastLib.toBytes32(_getActor()),
            amount, price
        );
    }

    /// @dev Full redeem cycle: request → approve → revoke → notify
    function shortcut_redeem_approve_revoke(uint128 amount, uint128 priceRaw) public poolExists {
        amount = _clampAmount(amount);
        priceRaw = _clampU128(priceRaw, 0.01e18, 100e18);
        D18 price = D18.wrap(priceRaw);

        _shortcutFullRedeem(
            activePoolId, activeScId, activeAssetId,
            CastLib.toBytes32(_getActor()),
            amount, price
        );
    }
}
