// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera deps
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {AccountId} from "src/core/types/AccountId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";

// Utils
import {BeforeAfter} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";

/// @title DoomsdayTargets
/// @notice Differential and edge-case testing targets for extreme scenarios.
abstract contract DoomsdayTargets is BaseTargetFunctions, Properties {
    /// @dev Property: accounting.accountValue should never revert (except AccountDoesNotExist)
    function accounting_accountValue(uint64 poolIdAsUint, uint32 accountAsInt) public {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        AccountId account = AccountId.wrap(accountAsInt);

        try accounting.accountValue(poolId, account) {} catch (bytes memory reason) {
            bool expectedRevert = checkError(reason, "AccountDoesNotExist()");
            t(expectedRevert, "Doomsday: accountValue unexpected revert");
        }
    }

    /// @dev Property: BRM epoch view functions should never revert for valid pools
    function brm_epoch_view_never_reverts(uint64 poolIdAsUint, bytes16 scIdAsBytes, uint128 assetIdAsUint) public {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        // These should always return a value, even for uninitialized state
        try brm.nowDepositEpoch(poolId, ShareClassId.wrap(scIdAsBytes), AssetId.wrap(assetIdAsUint)) {} catch {
            t(false, "Doomsday: nowDepositEpoch reverted");
        }
        try brm.nowIssueEpoch(poolId, ShareClassId.wrap(scIdAsBytes), AssetId.wrap(assetIdAsUint)) {} catch {
            t(false, "Doomsday: nowIssueEpoch reverted");
        }
        try brm.nowRedeemEpoch(poolId, ShareClassId.wrap(scIdAsBytes), AssetId.wrap(assetIdAsUint)) {} catch {
            t(false, "Doomsday: nowRedeemEpoch reverted");
        }
        try brm.nowRevokeEpoch(poolId, ShareClassId.wrap(scIdAsBytes), AssetId.wrap(assetIdAsUint)) {} catch {
            t(false, "Doomsday: nowRevokeEpoch reverted");
        }
    }

    /// @dev Property: NAV should be calculable for initialized networks
    function nav_value_calculable(uint64 poolIdAsUint, uint16 centrifugeId) public {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        try navManager.netAssetValue(poolId, centrifugeId) {} catch (bytes memory reason) {
            // NAV can fail if network not initialized — that's expected
            bool expectedRevert =
                checkError(reason, "NotInitialized()") || checkError(reason, "AccountDoesNotExist()");
            t(expectedRevert, "Doomsday: NAV unexpected revert");
        }
    }
}
