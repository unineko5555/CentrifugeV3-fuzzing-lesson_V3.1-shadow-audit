// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";

import {PoolId} from "src/core/types/PoolId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {D18} from "src/misc/types/D18.sol";

import {Properties} from "../properties/Properties.sol";
import {OpType} from "../BeforeAfter.sol";

/// @dev BalanceSheet targets — NEW in v3.1
abstract contract BalanceSheetTargets is BaseTargetFunctions, Properties {
    /// @dev Issue shares to actor
    function balanceSheet_issue(uint128 shares) public updateGhostsWithType(OpType.ADMIN) asAdmin {
        balanceSheet.issue(PoolId.wrap(poolId), ShareClassId.wrap(scId), _getActor(), shares);
        shareMints[address(token)] += shares;
    }

    /// @dev Revoke (burn) shares
    function balanceSheet_revoke(uint128 shares) public updateGhostsWithType(OpType.ADMIN) asAdmin {
        balanceSheet.revoke(PoolId.wrap(poolId), ShareClassId.wrap(scId), shares);
        executedRedemptions[address(token)] += shares;
    }

    /// @dev Override price per asset (transient — same tx only)
    function balanceSheet_overridePricePoolPerAsset(uint128 price)
        public
        updateGhostsWithType(OpType.ADMIN)
        asAdmin
    {
        balanceSheet.overridePricePoolPerAsset(
            PoolId.wrap(poolId), ShareClassId.wrap(scId), AssetId.wrap(assetId), D18.wrap(price)
        );
    }

    /// @dev Override price per share (transient — same tx only)
    function balanceSheet_overridePricePoolPerShare(uint128 price)
        public
        updateGhostsWithType(OpType.ADMIN)
        asAdmin
    {
        balanceSheet.overridePricePoolPerShare(PoolId.wrap(poolId), ShareClassId.wrap(scId), D18.wrap(price));
    }

    /// @dev Update manager flag
    function balanceSheet_updateManager(address who, bool canManage) public asAdmin {
        balanceSheet.updateManager(PoolId.wrap(poolId), who, canManage);
    }

    /// @dev Submit queued asset changes to hub
    function balanceSheet_submitQueuedAssets(uint128 extraGasLimit)
        public
        updateGhostsWithType(OpType.ADMIN)
        asAdmin
    {
        try balanceSheet.submitQueuedAssets(
            PoolId.wrap(poolId), ShareClassId.wrap(scId), AssetId.wrap(assetId), extraGasLimit, address(this)
        ) {} catch {}
    }

    /// @dev Submit queued share changes to hub
    function balanceSheet_submitQueuedShares(uint128 extraGasLimit)
        public
        updateGhostsWithType(OpType.ADMIN)
        asAdmin
    {
        try balanceSheet.submitQueuedShares(PoolId.wrap(poolId), ShareClassId.wrap(scId), extraGasLimit, address(this))
        {} catch {}
    }

    /// @dev Reset transient price override for asset
    function balanceSheet_resetPricePoolPerAsset() public updateGhostsWithType(OpType.ADMIN) asAdmin {
        balanceSheet.resetPricePoolPerAsset(PoolId.wrap(poolId), ShareClassId.wrap(scId), AssetId.wrap(assetId));
    }

    /// @dev Transfer shares between addresses
    function balanceSheet_transferSharesFrom(address from, address to, uint256 amount)
        public
        updateGhostsWithType(OpType.ADMIN)
        asAdmin
    {
        try balanceSheet.transferSharesFrom(
            PoolId.wrap(poolId), ShareClassId.wrap(scId), address(this), from, to, amount
        ) {} catch {}
    }
}
