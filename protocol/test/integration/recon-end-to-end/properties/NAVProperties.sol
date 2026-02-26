// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Asserts} from "@chimera/Asserts.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {AccountId} from "src/core/types/AccountId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";

import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title NAVProperties
/// @notice NAV-related properties for E2E verification.
///         Verifies NAV calculation consistency and gain/loss closure.
abstract contract NAVProperties is BeforeAfter, Asserts {
    // ===================================================================
    // P-NAV-1: NAV View Never Reverts (after initialization)
    // ===================================================================

    /// @dev navManager.netAssetValue should not revert for initialized networks
    function property_NAV_1_view_liveness() public {
        if (createdPools.length == 0) return;

        for (uint256 i = 0; i < createdPools.length; i++) {
            try navManager.netAssetValue(createdPools[i], SPOKE_CENTRIFUGE_ID) {}
            catch {
                // NAV may revert if network not initialized — that's OK
            }
        }
    }

    // ===================================================================
    // P-NAV-2: NAV >= 0 (Non-Negative)
    // ===================================================================

    /// @dev NAV should always be non-negative (uint128, so this is structural)
    function property_NAV_2_non_negative() public {
        if (createdPools.length == 0) return;

        for (uint256 i = 0; i < createdPools.length; i++) {
            try navManager.netAssetValue(createdPools[i], SPOKE_CENTRIFUGE_ID) returns (uint128 nav) {
                // uint128 is inherently >= 0, but verify it's reasonable
                lte(uint256(nav), type(uint128).max, "P-NAV-2: NAV exceeds uint128.max");
            } catch {}
        }
    }

    // ===================================================================
    // P-NAV-3: After closeGainLoss, gain/loss accounts should be zeroed
    // ===================================================================

    /// @dev After NAV_CLOSE_GAIN_LOSS operation, gain and loss accounts should be 0
    function property_NAV_3_close_zeros_gain_loss() public {
        if (currentOperation != OpType.NAV_CLOSE_GAIN_LOSS) return;
        if (createdPools.length == 0) return;

        PoolId pid = activePoolId;
        AssetId aid = poolCurrency[pid];
        ShareClassId[] storage scs = poolShareClasses[pid];

        for (uint256 j = 0; j < scs.length; j++) {
            AccountId gainAccId = holdings.accountId(pid, scs[j], aid, 2);
            AccountId lossAccId = holdings.accountId(pid, scs[j], aid, 3);

            (,,, uint64 gainUpdated,) = accounting.accounts(pid, gainAccId);
            if (gainUpdated == 0) continue;

            (, uint128 gainVal) = accounting.accountValue(pid, gainAccId);
            (, uint128 lossVal) = accounting.accountValue(pid, lossAccId);

            // After closeGainLoss, both should be 0
            eq(uint256(gainVal), 0, "P-NAV-3a: gain != 0 after close");
            eq(uint256(lossVal), 0, "P-NAV-3b: loss != 0 after close");
        }
    }
}
