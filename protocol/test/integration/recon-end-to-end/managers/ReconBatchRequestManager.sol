// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";

import {ReconPoolManager} from "./ReconPoolManager.sol";

/// @title ReconBatchRequestManager
/// @notice Epoch lifecycle shortcuts for deposit and redeem flows.
///         Wraps multi-step BRM operations into single convenience functions.
///         In E2E mode, issueShares/revokeShares automatically trigger cross-chain
///         messages to the spoke (notifyDeposit/notifyRedeem) via the real messaging stack.
abstract contract ReconBatchRequestManager is ReconPoolManager {
    using CastLib for *;

    /// @dev Run a full deposit epoch: approve deposits → issue shares
    ///      After issueShares, the Hub automatically sends notifyDeposit messages to spoke
    ///      via the real messaging stack.
    function _runDepositEpoch(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        uint128 approvedAssetAmount,
        D18 approvePrice,
        D18 issuePrice
    ) internal {
        // Step 1: approveDeposits (locks in deposit amounts)
        uint32 depositEpoch = brm.nowDepositEpoch(poolId, scId, assetId);
        try brm.approveDeposits(poolId, scId, assetId, depositEpoch, approvedAssetAmount, approvePrice, address(this)) {}
        catch {}

        // Step 2: issueShares (calculates shares, triggers cross-chain messages)
        uint32 issueEpoch = brm.nowIssueEpoch(poolId, scId, assetId);
        try brm.issueShares(poolId, scId, assetId, issueEpoch, issuePrice, 0, address(this)) {}
        catch {}
    }

    /// @dev Run a full redeem epoch: approve redeems → revoke shares
    ///      After revokeShares, the Hub automatically sends notifyRedeem messages to spoke.
    function _runRedeemEpoch(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        uint128 approvedShareAmount,
        D18 approvePrice,
        D18 revokePrice
    ) internal {
        // Step 1: approveRedeems (locks in redeem amounts)
        uint32 redeemEpoch = brm.nowRedeemEpoch(poolId, scId, assetId);
        try brm.approveRedeems(poolId, scId, assetId, redeemEpoch, approvedShareAmount, approvePrice) {}
        catch {}

        // Step 2: revokeShares (burns shares, triggers cross-chain messages)
        uint32 revokeEpoch = brm.nowRevokeEpoch(poolId, scId, assetId);
        try brm.revokeShares(poolId, scId, assetId, revokeEpoch, revokePrice, 0, address(this)) {}
        catch {}
    }

    /// @dev Notify deposit claims for a specific investor
    function _notifyDepositClaims(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        address investor,
        uint32 maxClaims
    ) internal {
        bytes32 investorBytes = CastLib.toBytes32(investor);
        try brm.notifyDeposit(poolId, scId, assetId, investorBytes, maxClaims, address(this)) {}
        catch {}
    }

    /// @dev Notify redeem claims for a specific investor
    function _notifyRedeemClaims(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        address investor,
        uint32 maxClaims
    ) internal {
        bytes32 investorBytes = CastLib.toBytes32(investor);
        try brm.notifyRedeem(poolId, scId, assetId, investorBytes, maxClaims, address(this)) {}
        catch {}
    }

    /// @dev Full deposit shortcut: request → approve → issue → notify → (spoke: claim on vault)
    function _shortcutFullDeposit(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        bytes32 investor,
        uint128 amount,
        D18 price
    ) internal {
        // Request
        try brm.requestDeposit(poolId, scId, amount, investor, assetId) {} catch {}

        // Approve + Issue
        _runDepositEpoch(poolId, scId, assetId, amount, price, price);

        // Notify for claim
        try brm.notifyDeposit(poolId, scId, assetId, investor, 10, address(this)) {} catch {}

        depositExecuted = true;
    }

    /// @dev Full redeem shortcut: request → approve → revoke → notify → (spoke: claim on vault)
    function _shortcutFullRedeem(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        bytes32 investor,
        uint128 amount,
        D18 price
    ) internal {
        // Request
        try brm.requestRedeem(poolId, scId, amount, investor, assetId) {} catch {}

        // Approve + Revoke
        _runRedeemEpoch(poolId, scId, assetId, amount, price, price);

        // Notify for claim
        try brm.notifyRedeem(poolId, scId, assetId, investor, 10, address(this)) {} catch {}

        redeemExecuted = true;
    }
}
