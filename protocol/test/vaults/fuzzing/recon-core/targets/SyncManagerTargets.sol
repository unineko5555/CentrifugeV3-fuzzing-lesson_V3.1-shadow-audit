// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";

import {PoolId} from "src/core/types/PoolId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AssetId} from "src/core/types/AssetId.sol";

import {Properties} from "../properties/Properties.sol";
import {OpType} from "../BeforeAfter.sol";

/// @dev SyncManager targets — NEW in v3.1
abstract contract SyncManagerTargets is BaseTargetFunctions, Properties {
    /// @dev Set max reserve for the current pool/scId/asset
    function syncManager_setMaxReserve(uint128 maxReserve_) public updateGhostsWithType(OpType.ADMIN) asAdmin {
        (address asset, uint256 tokenId) = spoke.idToAsset(AssetId.wrap(assetId));
        syncManager.setMaxReserve(PoolId.wrap(poolId), ShareClassId.wrap(scId), asset, tokenId, maxReserve_);
    }

    /// @dev Set valuation contract for sync deposits
    function syncManager_setValuation(address valuation_) public updateGhostsWithType(OpType.ADMIN) asAdmin {
        try syncManager.setValuation(PoolId.wrap(poolId), ShareClassId.wrap(scId), valuation_) {} catch {}
    }
}
