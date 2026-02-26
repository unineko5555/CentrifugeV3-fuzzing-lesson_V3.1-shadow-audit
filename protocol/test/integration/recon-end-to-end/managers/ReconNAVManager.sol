// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";

// Interfaces
import {IValuation} from "src/core/hub/interfaces/IValuation.sol";

import {ReconBatchRequestManager} from "./ReconBatchRequestManager.sol";

/// @title ReconNAVManager
/// @notice NAV initialization and management helpers for E2E fuzzing.
///         Wraps NAVManager operations that require specific initialization sequences.
abstract contract ReconNAVManager is ReconBatchRequestManager {
    /// @dev Initialize NAV for a pool's network (required before holdings can be initialized)
    function _initializeNAVNetwork(PoolId poolId, uint16 centrifugeId) internal {
        try navManager.initializeNetwork(poolId, centrifugeId) {} catch {}
    }

    /// @dev Initialize NAV holding for a specific (pool, shareClass, asset) tuple
    function _initializeNAVHolding(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        bool useIdentityValuation
    ) internal {
        IValuation valuation = useIdentityValuation
            ? IValuation(address(identityValuation))
            : IValuation(address(oracleValuation));
        try navManager.initializeHolding(poolId, scId, assetId, valuation) {} catch {}
    }

    /// @dev Full NAV setup for a pool: initialize network + holding
    function _setupNAV(PoolId poolId, ShareClassId scId, AssetId assetId) internal {
        _initializeNAVNetwork(poolId, SPOKE_CENTRIFUGE_ID);
        _initializeNAVHolding(poolId, scId, assetId, true);
    }

    /// @dev Update holding value and close gain/loss for a pool
    function _updateAndCloseNAV(PoolId poolId, ShareClassId scId, AssetId assetId) internal {
        try navManager.updateHoldingValue(poolId, scId, assetId) {} catch {}
        try navManager.closeGainLoss(poolId, SPOKE_CENTRIFUGE_ID) {} catch {}
    }
}
