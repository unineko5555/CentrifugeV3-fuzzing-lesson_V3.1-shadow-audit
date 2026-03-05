// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {IBaseVault} from "src/vaults/interfaces/IBaseVault.sol";
import {ISyncDepositValuation} from "src/vaults/interfaces/IVaultManagers.sol";
import {Properties} from "../properties/Properties.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title SyncManagerTargets
/// @notice Target functions for SyncManager operations: valuation, reserves, price views.
///         SyncManager is at 4.4% coverage — these targets exercise setValuation, setMaxReserve,
///         convertToShares/convertToAssets (→ PricingLib), pricePoolPerShare, and maxDeposit.
abstract contract SyncManagerTargets is BaseTargetFunctions, Properties {
    /// @dev Set valuation to address(0) → delegates to spoke.pricePoolPerShare (the meaningful path).
    ///      NOTE: IdentityValuation does NOT implement ISyncDepositValuation, so setting it
    ///      would cause silent reverts on pricePoolPerShare/convert calls. Using address(0)
    ///      exercises the spoke delegation path which is the production-default behavior.
    function sync_setValuation()
        public
        updateGhostsWithType(OpType.SYNC_DEPOSIT)
        poolExists
    {
        try syncManager.setValuation(
            activePoolId, activeScId, address(0)
        ) {} catch {}
    }

    /// @dev Set max reserve for the active pool/sc/asset
    function sync_setMaxReserve(uint128 maxReserve)
        public
        updateGhostsWithType(OpType.SYNC_DEPOSIT)
        poolExists
    {
        maxReserve = _clampU128(maxReserve, 1, uint128(1e30));
        (address asset, uint256 tokenId) = spoke.idToAsset(activeAssetId);
        if (asset == address(0)) return;

        try syncManager.setMaxReserve(
            activePoolId, activeScId, asset, tokenId, maxReserve
        ) {} catch {}
    }

    /// @dev Exercise SyncManager.convertToShares view (→ PricingLib.assetToShareAmount)
    function sync_convertToShares(uint128 assets) public poolExists {
        if (address(vault) == address(0)) return;
        assets = _clampU128(assets, 1, uint128(1e24));
        try syncManager.convertToShares(IBaseVault(address(vault)), uint256(assets)) {} catch {}
    }

    /// @dev Exercise SyncManager.convertToAssets view (→ PricingLib.shareToAssetAmount)
    function sync_convertToAssets(uint128 shares) public poolExists {
        if (address(vault) == address(0)) return;
        shares = _clampU128(shares, 1, uint128(1e24));
        try syncManager.convertToAssets(IBaseVault(address(vault)), uint256(shares)) {} catch {}
    }

    /// @dev Exercise SyncManager.pricePoolPerShare view (valuation delegation chain)
    function sync_pricePoolPerShare() public poolExists {
        try syncManager.pricePoolPerShare(activePoolId, activeScId) {} catch {}
    }

    /// @dev Exercise SyncManager.maxDeposit view (vaultRegistry.isLinked + maxReserve arithmetic)
    function sync_maxDeposit() public poolExists {
        if (address(vault) == address(0)) return;
        address actor = _getActor();
        try syncManager.maxDeposit(IBaseVault(address(vault)), actor) {} catch {}
    }
}
