// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";

import {Properties} from "../properties/Properties.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title HubTargets
/// @notice Hub-side target functions for E2E fuzzing.
///         Handles BRM notify (deposit/redeem claims), price updates via hub, and NAV operations.
///         In E2E mode, these operations trigger cross-chain messages to spoke automatically.
abstract contract HubTargets is BaseTargetFunctions, Properties {
    using CastLib for *;

    // ===================================================================
    // BRM Notify (claim triggers — sends messages to spoke)
    // ===================================================================

    /// @dev Notify deposit for the current actor — triggers cross-chain fulfillment
    function hub_notifyDeposit(uint32 maxClaims) public updateGhostsWithType(OpType.BRM_NOTIFY_DEPOSIT) poolExists {
        bytes32 investor = CastLib.toBytes32(_getActor());
        maxClaims = maxClaims == 0 ? MAX_CLAIMS : maxClaims;

        try brm.notifyDeposit(activePoolId, activeScId, activeAssetId, investor, maxClaims, address(this)) {
            depositExecuted = true;
        } catch {}
    }

    /// @dev Notify redeem for the current actor — triggers cross-chain fulfillment
    function hub_notifyRedeem(uint32 maxClaims) public updateGhostsWithType(OpType.BRM_NOTIFY_REDEEM) poolExists {
        bytes32 investor = CastLib.toBytes32(_getActor());
        maxClaims = maxClaims == 0 ? MAX_CLAIMS : maxClaims;

        try brm.notifyRedeem(activePoolId, activeScId, activeAssetId, investor, maxClaims, address(this)) {
            redeemExecuted = true;
        } catch {}
    }

    /// @dev Notify deposit for a specific actor by entropy
    function hub_notifyDeposit_forActor(uint256 actorEntropy, uint32 maxClaims)
        public
        updateGhostsWithType(OpType.BRM_NOTIFY_DEPOSIT)
        poolExists
    {
        address actor = _getRandomActor(actorEntropy);
        bytes32 investor = CastLib.toBytes32(actor);
        maxClaims = maxClaims == 0 ? MAX_CLAIMS : maxClaims;

        try brm.notifyDeposit(activePoolId, activeScId, activeAssetId, investor, maxClaims, address(this)) {}
        catch {}
    }

    /// @dev Notify redeem for a specific actor by entropy
    function hub_notifyRedeem_forActor(uint256 actorEntropy, uint32 maxClaims)
        public
        updateGhostsWithType(OpType.BRM_NOTIFY_REDEEM)
        poolExists
    {
        address actor = _getRandomActor(actorEntropy);
        bytes32 investor = CastLib.toBytes32(actor);
        maxClaims = maxClaims == 0 ? MAX_CLAIMS : maxClaims;

        try brm.notifyRedeem(activePoolId, activeScId, activeAssetId, investor, maxClaims, address(this)) {}
        catch {}
    }

    // ===================================================================
    // NAV Operations (Hub-side, via NAVManager)
    // ===================================================================

    /// @dev Initialize NAV network for the active pool
    function hub_nav_initializeNetwork() public updateGhostsWithType(OpType.NAV_UPDATE) poolExists {
        _initializeNAVNetwork(activePoolId, SPOKE_CENTRIFUGE_ID);
    }

    /// @dev Initialize NAV holding for the active pool/sc/asset
    function hub_nav_initializeHolding() public updateGhostsWithType(OpType.NAV_UPDATE) poolExists {
        _initializeNAVHolding(activePoolId, activeScId, activeAssetId, true);
    }

    /// @dev Update holding value via NAV manager
    function hub_nav_updateHoldingValue() public updateGhostsWithType(OpType.NAV_UPDATE) poolExists {
        try navManager.updateHoldingValue(activePoolId, activeScId, activeAssetId) {} catch {}
    }

    /// @dev Close gain/loss for the active pool
    function hub_nav_closeGainLoss() public updateGhostsWithType(OpType.NAV_CLOSE_GAIN_LOSS) poolExists {
        try navManager.closeGainLoss(activePoolId, SPOKE_CENTRIFUGE_ID) {} catch {}
    }

    /// @dev Get NAV for the active pool (view, for verification)
    function hub_nav_netAssetValue() public view poolExists returns (uint128) {
        return navManager.netAssetValue(activePoolId, SPOKE_CENTRIFUGE_ID);
    }

    // ===================================================================
    // Hub Accounting (Journal)
    // ===================================================================

    /// @dev Update share price via hub — propagated via messaging
    function hub_updateSharePrice(uint128 priceRaw)
        public
        updateGhostsWithType(OpType.ADMIN)
        poolExists
    {
        D18 price = D18.wrap(priceRaw);
        try hub.updateSharePrice(activePoolId, activeScId, price, uint64(block.timestamp)) {
            priceUpdated = true;
        } catch {}
    }

    /// @dev Update share price clamped to reasonable range
    function hub_updateSharePrice_clamped(uint128 priceEntropy) public {
        uint128 price = _clampU128(priceEntropy, 0.01e18, 100e18);
        hub_updateSharePrice(price);
    }
}
