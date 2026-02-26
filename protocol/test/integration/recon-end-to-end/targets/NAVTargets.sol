// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

// Types
import {D18, d18} from "src/misc/types/D18.sol";

// Interfaces
import {IValuation} from "src/core/hub/interfaces/IValuation.sol";

import {Properties} from "../properties/Properties.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title NAVTargets
/// @notice NAV Manager target functions for E2E fuzzing.
///         NAVManager handles accounting for pool networks, holdings, and gain/loss.
///         Also includes OracleValuation targets for price feed testing.
abstract contract NAVTargets is BaseTargetFunctions, Properties {
    // ===================================================================
    // NAV Initialization
    // ===================================================================

    /// @dev Initialize NAV network for the active pool on the spoke chain
    function nav_initializeNetwork() public updateGhostsWithType(OpType.NAV_UPDATE) poolExists {
        try navManager.initializeNetwork(activePoolId, SPOKE_CENTRIFUGE_ID) {} catch {}
    }

    /// @dev Initialize NAV holding for the active pool/sc/asset
    function nav_initializeHolding() public updateGhostsWithType(OpType.NAV_UPDATE) poolExists {
        try navManager.initializeHolding(
            activePoolId, activeScId, activeAssetId,
            IValuation(address(identityValuation))
        ) {} catch {}
    }

    // ===================================================================
    // NAV Operations
    // ===================================================================

    /// @dev Update holding value via NAV manager
    function nav_updateHoldingValue() public updateGhostsWithType(OpType.NAV_UPDATE) poolExists {
        try navManager.updateHoldingValue(activePoolId, activeScId, activeAssetId) {} catch {}
    }

    /// @dev Close gain/loss for the active pool
    function nav_closeGainLoss() public updateGhostsWithType(OpType.NAV_CLOSE_GAIN_LOSS) poolExists {
        try navManager.closeGainLoss(activePoolId, SPOKE_CENTRIFUGE_ID) {} catch {}
    }

    // ===================================================================
    // OracleValuation Operations
    // ===================================================================

    /// @dev Set oracle price for the active holding (test contract is feeder)
    function nav_setOraclePrice(uint128 priceRaw) public updateGhostsWithType(OpType.NAV_UPDATE) poolExists {
        priceRaw = _clampU128(priceRaw, 0.01e18, 100e18);
        try oracleValuation.setPrice(activePoolId, activeScId, activeAssetId, D18.wrap(priceRaw)) {
            priceUpdated = true;
        } catch {}
    }

    /// @dev Switch holding valuation from identity to oracle (via NAVManager)
    function nav_switchToOracleValuation() public updateGhostsWithType(OpType.NAV_UPDATE) poolExists {
        try navManager.updateHoldingValuation(
            activePoolId, activeScId, activeAssetId,
            IValuation(address(oracleValuation))
        ) {} catch {}
    }

    /// @dev Switch holding valuation from oracle back to identity (via NAVManager)
    function nav_switchToIdentityValuation() public updateGhostsWithType(OpType.NAV_UPDATE) poolExists {
        try navManager.updateHoldingValuation(
            activePoolId, activeScId, activeAssetId,
            IValuation(address(identityValuation))
        ) {} catch {}
    }

    // ===================================================================
    // NAV View (verification helpers)
    // ===================================================================

    /// @dev Get NAV for the active pool (view, for verification)
    function nav_netAssetValue() public view poolExists returns (uint128) {
        return navManager.netAssetValue(activePoolId, SPOKE_CENTRIFUGE_ID);
    }
}
