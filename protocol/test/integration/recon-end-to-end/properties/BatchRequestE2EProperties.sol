// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Asserts} from "@chimera/Asserts.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";

import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title BatchRequestE2EProperties
/// @notice BRM E2E properties that verify full cycle conservation
///         and epoch ordering across Hub↔Spoke.
abstract contract BatchRequestE2EProperties is BeforeAfter, Asserts {
    // ===================================================================
    // P-BRM-E2E-1: Pending Deposit Accounting
    // ===================================================================

    /// @dev pendingDeposit >= sum of all user deposit requests.
    ///      Only valid before first approval (epochs == 1) — after approval, aggregate
    ///      pending is reduced but individual user pending stays until claim.
    function property_BRM_E2E_1_pending_deposit_accounting() public {
        if (createdPools.length == 0) return;

        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId pid = createdPools[i];
            AssetId aid = poolCurrency[pid];
            ShareClassId[] storage scs = poolShareClasses[pid];

            for (uint256 j = 0; j < scs.length; j++) {
                (uint32 dEp, uint32 iEp,,) = brm.epochId(pid, scs[j], aid);
                if (dEp > 0 || iEp > 0) continue;

                uint128 pending = brm.pendingDeposit(pid, scs[j], aid);

                uint128 userSum = 0;
                address[] memory actors = _getActors();
                for (uint256 k = 0; k < actors.length; k++) {
                    (uint128 userPending,) = brm.depositRequest(pid, scs[j], aid, CastLib.toBytes32(actors[k]));
                    userSum += userPending;
                }

                gte(uint256(pending), uint256(userSum), "P-BRM-E2E-1: pendingDeposit < sum(users)");
            }
        }
    }

    // ===================================================================
    // P-BRM-E2E-2: Pending Redeem Accounting
    // ===================================================================

    /// @dev pendingRedeem >= sum of all user redeem requests.
    ///      Only valid before first approval (epochs == 1) — after approval, aggregate
    ///      pending is reduced but individual user pending stays until claim.
    function property_BRM_E2E_2_pending_redeem_accounting() public {
        if (createdPools.length == 0) return;

        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId pid = createdPools[i];
            AssetId aid = poolCurrency[pid];
            ShareClassId[] storage scs = poolShareClasses[pid];

            for (uint256 j = 0; j < scs.length; j++) {
                (,, uint32 rEp, uint32 rvEp) = brm.epochId(pid, scs[j], aid);
                if (rEp > 0 || rvEp > 0) continue;

                uint128 pending = brm.pendingRedeem(pid, scs[j], aid);

                uint128 userSum = 0;
                address[] memory actors = _getActors();
                for (uint256 k = 0; k < actors.length; k++) {
                    (uint128 userPending,) = brm.redeemRequest(pid, scs[j], aid, CastLib.toBytes32(actors[k]));
                    userSum += userPending;
                }

                gte(uint256(pending), uint256(userSum), "P-BRM-E2E-2: pendingRedeem < sum(users)");
            }
        }
    }

    // ===================================================================
    // P-BRM-E2E-3: Epoch Ordering
    // ===================================================================

    /// @dev deposit.epoch >= deposit.issue.epoch (can't issue before deposit phase)
    ///      redeem.epoch >= redeem.revoke.epoch (can't revoke before redeem phase)
    function property_BRM_E2E_3_epoch_ordering() public {
        if (createdPools.length == 0) return;

        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId pid = createdPools[i];
            AssetId aid = poolCurrency[pid];
            ShareClassId[] storage scs = poolShareClasses[pid];

            for (uint256 j = 0; j < scs.length; j++) {
                uint32 nowDep = brm.nowDepositEpoch(pid, scs[j], aid);
                uint32 nowIssue = brm.nowIssueEpoch(pid, scs[j], aid);
                uint32 nowRedeem = brm.nowRedeemEpoch(pid, scs[j], aid);
                uint32 nowRevoke = brm.nowRevokeEpoch(pid, scs[j], aid);

                gte(uint256(nowDep), uint256(nowIssue), "P-BRM-E2E-3a: nowDeposit < nowIssue");
                gte(uint256(nowRedeem), uint256(nowRevoke), "P-BRM-E2E-3b: nowRedeem < nowRevoke");
            }
        }
    }

    // ===================================================================
    // P-BRM-E2E-4: Cancel Preserves No More Than Requested
    // ===================================================================

    /// @dev After cancel: user's pending should have decreased (or be 0)
    function property_BRM_E2E_4_cancel_reduces_pending() public {
        if (currentOperation != OpType.BRM_CANCEL_DEPOSIT && currentOperation != OpType.BRM_CANCEL_REDEEM) return;
        if (createdPools.length == 0) return;

        address[] memory actors = _getActors();
        for (uint256 k = 0; k < actors.length; k++) {
            bytes32 actor = CastLib.toBytes32(actors[k]);

            if (currentOperation == OpType.BRM_CANCEL_DEPOSIT) {
                uint128 afterPending = _after.hubDepositRequest[activeScId][activeAssetId][actor].pending;
                uint128 beforePending = _before.hubDepositRequest[activeScId][activeAssetId][actor].pending;
                lte(uint256(afterPending), uint256(beforePending), "P-BRM-E2E-4: deposit pending increased after cancel");
            }
            if (currentOperation == OpType.BRM_CANCEL_REDEEM) {
                uint128 afterPending = _after.hubRedeemRequest[activeScId][activeAssetId][actor].pending;
                uint128 beforePending = _before.hubRedeemRequest[activeScId][activeAssetId][actor].pending;
                lte(uint256(afterPending), uint256(beforePending), "P-BRM-E2E-4: redeem pending increased after cancel");
            }
        }
    }
}
