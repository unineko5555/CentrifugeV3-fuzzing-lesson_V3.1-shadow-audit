// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

// Types
import {AssetId} from "src/core/types/AssetId.sol";

import {Properties} from "../properties/Properties.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title QueueManagerTargets
/// @notice QueueManager target functions for E2E fuzzing.
///         QueueManager batches asset/share queue submissions into a single cross-chain sync.
abstract contract QueueManagerTargets is BaseTargetFunctions, Properties {
    // ===================================================================
    // Queue Sync (batched cross-chain submission)
    // ===================================================================

    /// @dev Sync all queued assets and shares for the active pool/shareClass
    function queue_sync() public updateGhostsWithType(OpType.BS_SUBMIT_QUEUED_ASSETS) poolExists {
        AssetId[] memory assetIds = new AssetId[](1);
        assetIds[0] = activeAssetId;

        try queueManager.sync{value: 0}(activePoolId, activeScId, assetIds, address(this)) {} catch {}
    }

    /// @dev Sync with multiple asset IDs (if pool has multiple assets)
    function queue_syncMultiAsset() public updateGhostsWithType(OpType.BS_SUBMIT_QUEUED_ASSETS) poolExists {
        // Build array of all known asset IDs for this pool
        AssetId[] memory assetIds = new AssetId[](1);
        assetIds[0] = poolCurrency[activePoolId];

        try queueManager.sync{value: 0}(activePoolId, activeScId, assetIds, address(this)) {} catch {}
    }
}
