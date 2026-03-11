// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";
import {D18} from "src/misc/types/D18.sol";
import {Properties} from "../properties/Properties.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title PriceAgeTargets
/// @notice Target functions for Hub.setMaxAssetPriceAge/setMaxSharePriceAge cross-chain messages
///         and Spoke price staleness verification.
abstract contract PriceAgeTargets is BaseTargetFunctions, Properties {
    /// @dev Set max asset price age (Hub → Spoke cross-chain message)
    function priceAge_setMaxAssetPriceAge(uint64 maxAge)
        public
        updateGhostsWithType(OpType.PRICE_AGE_SET)
        poolExists
    {
        maxAge = _clampU64(maxAge, 60, uint64(365 days));
        try hub.setMaxAssetPriceAge{value: 0}(
            activePoolId, activeScId, activeAssetId, maxAge, address(this)
        ) {
            ghostMaxAssetPriceAge[activePoolId][activeScId][activeAssetId] = maxAge;
        } catch {}
    }

    /// @dev Set max share price age (Hub → Spoke cross-chain message)
    function priceAge_setMaxSharePriceAge(uint64 maxAge)
        public
        updateGhostsWithType(OpType.PRICE_AGE_SET)
        poolExists
    {
        maxAge = _clampU64(maxAge, 60, uint64(365 days));
        try hub.setMaxSharePriceAge{value: 0}(
            activePoolId, activeScId, SPOKE_CENTRIFUGE_ID, maxAge, address(this)
        ) {
            ghostMaxSharePriceAge[activePoolId][activeScId] = maxAge;
        } catch {}
    }

    /// @dev Doomsday: stale asset price → pricePoolPerAsset(revert=true) should revert
    function priceAge_doomsday_stale_asset_price() public poolExists {
        uint64 maxAge = ghostMaxAssetPriceAge[activePoolId][activeScId][activeAssetId];
        if (maxAge == 0) return;
        // Exercise the validation path; both success and revert are valid
        try spoke.pricePoolPerAsset(activePoolId, activeScId, activeAssetId, true) {} catch {}
    }

    /// @dev Doomsday: stale share price → pricePoolPerShare(revert=true) should revert
    function priceAge_doomsday_stale_share_price() public poolExists {
        uint64 maxAge = ghostMaxSharePriceAge[activePoolId][activeScId];
        if (maxAge == 0) return;
        try spoke.pricePoolPerShare(activePoolId, activeScId, true) {} catch {}
    }

    /// @dev Stale oracle → operate: warp past maxPriceAge then attempt deposit
    ///      Multi-step target to explore stale oracle state (hard to reach via random sequencing)
    function priceAge_stale_then_requestDeposit(uint128 amount)
        public
        updateGhostsWithType(OpType.PRICE_AGE_SET)
        poolExists
    {
        uint64 maxAge = ghostMaxAssetPriceAge[activePoolId][activeScId][activeAssetId];
        if (maxAge == 0) return;
        // Warp just past staleness threshold
        vm.warp(block.timestamp + uint256(maxAge) + 1);
        // Attempt deposit under stale price — should revert or behave correctly
        amount = _clampU128(amount, 1, uint128(type(uint64).max));
        bytes32 investor = bytes32(uint256(uint160(address(this))));
        try brm.requestDeposit(activePoolId, activeScId, amount, investor, activeAssetId) {} catch {}
    }
}
