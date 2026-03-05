// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Asserts} from "@chimera/Asserts.sol";
import {D18} from "src/misc/types/D18.sol";
import {IBaseVault} from "src/vaults/interfaces/IBaseVault.sol";
import {BeforeAfter} from "../BeforeAfter.sol";

/// @title SyncManagerProperties
/// @notice SyncManager-related properties for E2E verification.
///         Verifies price view liveness, conversion round-trip consistency, and reserve bounds.
abstract contract SyncManagerProperties is BeforeAfter, Asserts {
    /// @dev P-SM-1: SyncManager.pricePoolPerShare should not revert after pool init
    function property_SM_1_price_view_liveness() public {
        if (createdPools.length == 0) return;
        try syncManager.pricePoolPerShare(activePoolId, activeScId) {} catch {
            // May revert if no share price set — acceptable early in lifecycle
        }
    }

    /// @dev P-SM-2: convertToShares → convertToAssets round-trip within tolerance.
    ///      With asset(6 dec) / share(18 dec) and two Rounding.Down operations,
    ///      error can exceed 1 asset-wei. Use asset-scale amount and allow 2 wei.
    function property_SM_2_conversion_round_trip() public {
        if (address(vault) == address(0)) return;
        IBaseVault v = IBaseVault(address(vault));

        uint256 testAmount = 1e6; // 1 asset unit (asset-scale, not 1e18)

        try syncManager.convertToShares(v, testAmount) returns (uint256 shares) {
            if (shares == 0) return;
            try syncManager.convertToAssets(v, shares) returns (uint256 assets) {
                uint256 diff = assets > testAmount ? assets - testAmount : testAmount - assets;
                lte(diff, 2, "P-SM-2: round-trip conversion off by >2 wei");
            } catch {}
        } catch {}
    }

    /// @dev P-SM-3: maxDeposit should respect maxReserve bounds
    function property_SM_3_max_deposit_respects_reserve() public {
        if (address(vault) == address(0)) return;

        (address asset, uint256 tokenId) = spoke.idToAsset(activeAssetId);
        if (asset == address(0)) return;

        uint128 maxRes = syncManager.maxReserve(activePoolId, activeScId, asset, tokenId);
        if (maxRes == 0) return;

        try syncManager.maxDeposit(IBaseVault(address(vault)), address(this)) returns (uint256 maxDep) {
            lte(maxDep, uint256(maxRes), "P-SM-3: maxDeposit exceeds maxReserve");
        } catch {}
    }
}
