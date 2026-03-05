// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {AssetId, newAssetId} from "src/core/types/AssetId.sol";
import {IValuation} from "src/core/hub/interfaces/IValuation.sol";
import {Properties} from "../properties/Properties.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title LiabilityTargets
/// @notice Target functions for NAVManager.initializeLiability, Hub.updateHoldingIsLiability,
///         and Holdings.isLiability paths.
abstract contract LiabilityTargets is BaseTargetFunctions, Properties {
    AssetId internal liabilityAssetId;
    bool internal liabilityAssetRegistered;
    bool internal liabilityHoldingInitialized;

    /// @dev Register a separate asset for liability use
    function liability_registerAsset()
        public
        updateGhostsWithType(OpType.LIABILITY_INIT)
        poolExists
    {
        if (liabilityAssetRegistered) return;
        liabilityAssetId = newAssetId(SPOKE_CENTRIFUGE_ID, ASSET_ID_COUNTER);
        ASSET_ID_COUNTER++;
        hubRegistry.registerAsset(liabilityAssetId, 18);
        liabilityAssetRegistered = true;
    }

    /// @dev Initialize a liability holding via NAVManager
    function liability_initializeLiability()
        public
        updateGhostsWithType(OpType.LIABILITY_INIT)
        poolExists
    {
        if (!liabilityAssetRegistered || liabilityHoldingInitialized) return;
        try navManager.initializeLiability(
            activePoolId, activeScId, liabilityAssetId,
            IValuation(address(identityValuation))
        ) {
            liabilityHoldingInitialized = true;
            liabilityInitialized = true;
        } catch {}
    }

    /// @dev Toggle holding between asset and liability mode (requires value == 0)
    function liability_toggleIsLiability(bool isLiability)
        public
        updateGhostsWithType(OpType.LIABILITY_INIT)
        poolExists
    {
        if (!liabilityHoldingInitialized) return;
        try hub.updateHoldingIsLiability(activePoolId, activeScId, liabilityAssetId, isLiability) {}
        catch {}
    }

    /// @dev Verify liability holding functions are accessible
    function liability_doomsday_isLiability_works() public poolExists {
        if (!liabilityHoldingInitialized) return;
        try holdings.isLiability(activePoolId, activeScId, liabilityAssetId) {} catch {
            revert("liability: isLiability reverted on initialized holding");
        }
    }
}
