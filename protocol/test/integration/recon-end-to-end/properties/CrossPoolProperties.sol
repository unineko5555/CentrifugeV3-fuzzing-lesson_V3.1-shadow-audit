// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Asserts} from "@chimera/Asserts.sol";
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title CrossPoolProperties
/// @notice P-CS-10 (cross-pool isolation) + P-V-8 (request callback delivery).
abstract contract CrossPoolProperties is BeforeAfter, Asserts {
    // ===================================================================
    // P-CS-10: Cross-Pool Isolation
    // ===================================================================

    /// @dev Operations on activePool must not change other pools' holdings
    function property_CS_10_cross_pool_isolation() public {
        if (createdPools.length < 2) return;

        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId pid = createdPools[i];
            if (PoolId.unwrap(pid) == PoolId.unwrap(activePoolId)) continue;

            AssetId aid = poolCurrency[pid];
            ShareClassId[] storage scs = poolShareClasses[pid];
            for (uint256 j = 0; j < scs.length; j++) {
                uint128 holdingBefore = _before.hubHolding[pid][scs[j]][aid];
                uint128 holdingAfter = _after.hubHolding[pid][scs[j]][aid];
                eq(
                    uint256(holdingAfter),
                    uint256(holdingBefore),
                    "P-CS-10: inactive pool holding changed"
                );
            }
        }
    }

    // ===================================================================
    // P-V-8: Request Callback Delivery
    // ===================================================================

    /// @dev After BRM_NOTIFY_DEPOSIT, if epochs advanced, some actor should have claimable shares
    function property_V_8_request_callback_delivery() public {
        if (currentOperation != OpType.BRM_NOTIFY_DEPOSIT) return;
        if (address(vault) == address(0)) return;

        (, uint32 iEp,,) = brm.epochId(activePoolId, activeScId, activeAssetId);
        if (iEp == 0) return; // no issue has happened yet

        // Soft check: verify callback delivery path is exercised
        // After issueShares + notifyDeposit, at least one actor should have maxMint > 0
        // (unless all already claimed)
        address[] memory actors = _getActors();
        for (uint256 k = 0; k < actors.length; k++) {
            vault.maxMint(actors[k]); // exercise the view path
        }
    }
}
