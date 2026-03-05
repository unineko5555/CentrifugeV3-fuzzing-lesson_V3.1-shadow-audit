// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";
import {MockERC20} from "@recon/MockERC20.sol";

import {PoolId} from "src/core/types/PoolId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {IBaseVault} from "src/vaults/interfaces/IBaseVault.sol";

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

    /// @dev SyncManager deposit — test contract is warded as deployer
    function syncManager_deposit(uint128 assets) public updateGhostsWithType(OpType.ADMIN) asAdmin {
        (address asset,) = spoke.idToAsset(AssetId.wrap(assetId));
        uint256 available = MockERC20(asset).balanceOf(_getActor());
        if (available == 0) return;
        assets = uint128(uint256(assets) % available);
        if (assets == 0) assets = 1;

        // Transfer assets to poolEscrow (SyncManager.deposit expects them there)
        address poolEscrowAddr = address(balanceSheet.escrow(PoolId.wrap(poolId)));
        vm.prank(_getActor());
        MockERC20(asset).transfer(poolEscrowAddr, assets);

        try syncManager.deposit(IBaseVault(address(vault)), assets, _getActor(), _getActor()) returns (uint256 shares) {
            // SyncManager._issueShares → balanceSheet.issue (mints shares) + noteDeposit (increases PE total)
            shareMints[address(token)] += shares;
            // Assets are now in PoolEscrow — available for redeem claims (property_global_2)
            mintedByCurrencyPayout[asset] += assets;
        } catch {}
    }

    /// @dev SyncManager mint
    function syncManager_mint(uint128 shares) public updateGhostsWithType(OpType.ADMIN) asAdmin {
        shares = uint128(uint256(shares) % 1_000_000e18) + 1;

        (address asset,) = spoke.idToAsset(AssetId.wrap(assetId));
        address poolEscrowAddr = address(balanceSheet.escrow(PoolId.wrap(poolId)));
        uint256 available = MockERC20(asset).balanceOf(_getActor());
        if (available == 0) return;

        // SyncManager.mint → _issueShares → noteDeposit(previewMint(shares))
        // noteDeposit inflates holding.total — MUST ensure previewMint(shares) <= transferred
        // Otherwise PE_2 (actualBalance >= holding.total) fails
        try syncManager.previewMint(IBaseVault(address(vault)), _getActor(), shares) returns (uint256 needed) {
            if (needed > available) return; // Can't afford these shares, skip
        } catch { return; }

        vm.prank(_getActor());
        MockERC20(asset).transfer(poolEscrowAddr, available);

        try syncManager.mint(IBaseVault(address(vault)), shares, _getActor(), _getActor()) returns (uint256 actualAssets) {
            // SyncManager._issueShares → balanceSheet.issue (mints shares) + noteDeposit (increases PE total)
            shareMints[address(token)] += shares;
            mintedByCurrencyPayout[asset] += actualAssets;
        } catch {}
    }

    /// @dev SyncManager view targets for coverage
    function syncManager_views() public view {
        IBaseVault v = IBaseVault(address(vault));
        address actor = _getActor();
        try syncManager.maxDeposit(v, actor) {} catch {}
        try syncManager.maxMint(v, actor) {} catch {}
        try syncManager.convertToShares(v, 1e18) {} catch {}
        try syncManager.convertToAssets(v, 1e18) {} catch {}
        try syncManager.previewDeposit(v, actor, 1e18) {} catch {}
        try syncManager.previewMint(v, actor, 1e18) {} catch {}
    }
}
