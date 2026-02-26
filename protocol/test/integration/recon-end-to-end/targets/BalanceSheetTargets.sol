// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {D18, d18} from "src/misc/types/D18.sol";

import {Properties} from "../properties/Properties.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title BalanceSheetTargets
/// @notice BalanceSheet target functions for E2E fuzzing (new in v3.1).
///         BalanceSheet manages share/asset state on the spoke side,
///         and can submit queued changes to hub via cross-chain messaging.
abstract contract BalanceSheetTargets is BaseTargetFunctions, Properties {
    // ===================================================================
    // Queue Submission (cross-chain: sends queued deltas to hub)
    // ===================================================================

    /// @dev Submit queued asset changes to hub
    function bs_submitQueuedAssets() public updateGhostsWithType(OpType.BS_SUBMIT_QUEUED_ASSETS) poolExists {
        try balanceSheet.submitQueuedAssets{value: 0}(activePoolId, activeScId, activeAssetId, 0, address(this)) {}
        catch {}
    }

    /// @dev Submit queued share changes to hub
    function bs_submitQueuedShares() public updateGhostsWithType(OpType.BS_SUBMIT_QUEUED_SHARES) poolExists {
        try balanceSheet.submitQueuedShares{value: 0}(activePoolId, activeScId, 0, address(this)) {}
        catch {}
    }

    // ===================================================================
    // Price Overrides (transient, same-tx only)
    // ===================================================================

    /// @dev Override price per asset (transient EIP-1153)
    function bs_overridePricePoolPerAsset(uint128 priceRaw) public updateGhosts poolExists {
        priceRaw = _clampU128(priceRaw, 0.01e18, 100e18);
        try balanceSheet.overridePricePoolPerAsset(activePoolId, activeScId, activeAssetId, D18.wrap(priceRaw)) {}
        catch {}
    }

    /// @dev Override price per share (transient EIP-1153)
    function bs_overridePricePoolPerShare(uint128 priceRaw) public updateGhosts poolExists {
        priceRaw = _clampU128(priceRaw, 0.01e18, 100e18);
        try balanceSheet.overridePricePoolPerShare(activePoolId, activeScId, D18.wrap(priceRaw)) {}
        catch {}
    }

    // ===================================================================
    // Share Management
    // ===================================================================

    /// @dev Transfer shares from one actor to another
    function bs_transferSharesFrom(uint256 actorEntropy, uint128 amount) public updateGhosts poolExists vaultExists {
        address from = _getActor();
        address to = _getRandomActor(actorEntropy);
        if (from == to) return;

        amount = _clampAmount(amount);
        try balanceSheet.transferSharesFrom(activePoolId, activeScId, address(this), from, to, uint256(amount)) {}
        catch {}
    }
}
