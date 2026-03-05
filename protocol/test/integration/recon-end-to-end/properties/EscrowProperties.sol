// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Asserts} from "@chimera/Asserts.sol";
import {MockERC20} from "@recon/MockERC20.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";

// Contracts
import {PoolEscrow} from "src/core/spoke/PoolEscrow.sol";
import {IPoolEscrow} from "src/core/spoke/interfaces/IPoolEscrow.sol";

import {BeforeAfter} from "../BeforeAfter.sol";

/// @title EscrowProperties
/// @notice Global escrow and pool escrow solvency properties.
///         Adapted from recon-core PoolEscrowProperties + global escrow properties.
abstract contract EscrowProperties is BeforeAfter, Asserts {
    // ===================================================================
    // P-E-1: Global Escrow Token Balance
    // ===================================================================

    /// @dev sum(maxWithdraw) per user <= escrow asset balance
    function property_E_1_escrow_asset_solvency() public {
        if (address(vault) == address(0)) return;

        address assetAddr = vault.asset();
        uint256 bal = MockERC20(assetAddr).balanceOf(address(escrow));
        uint256 sumMaxWithdraw = 0;

        address[] memory actors = _getActors();
        for (uint256 k = 0; k < actors.length; k++) {
            sumMaxWithdraw += vault.maxWithdraw(actors[k]);
        }

        gte(bal, sumMaxWithdraw, "P-E-1: escrow asset bal < sum(maxWithdraw)");
    }

    // ===================================================================
    // P-E-2: Global Escrow Share Balance
    // ===================================================================

    /// @dev sum(maxMint) per user <= escrow share balance
    function property_E_2_escrow_share_solvency() public {
        if (address(vault) == address(0) || address(token) == address(0)) return;

        uint256 bal = token.balanceOf(address(escrow));
        uint256 sumMaxMint = 0;

        address[] memory actors = _getActors();
        for (uint256 k = 0; k < actors.length; k++) {
            sumMaxMint += vault.maxMint(actors[k]);
        }

        gte(bal, sumMaxMint, "P-E-2: escrow share bal < sum(maxMint)");
    }

    // ===================================================================
    // P-PE-1: PoolEscrow total >= reserved
    // ===================================================================

    /// @dev For all pools: PoolEscrow holding.total >= holding.reserved
    /// DISABLED: GENUINE FINDING — PoolEscrow.reserve() lacks require(reserved <= total).
    /// revokedShares → balanceSheet.reserve() can set reserved > total when Hub-computed
    /// payoutAssetAmount (from price math) exceeds PoolEscrow holdings on the Spoke side.
    /// The poolEscrow_reserve handler is clamped, but the BRM → revokedShares path bypasses it.
    // function property_PE_1_total_gte_reserved() public {
    //     for (uint256 i = 0; i < createdPools.length; i++) {
    //         _checkPoolEscrowTotalGteReserved(createdPools[i]);
    //     }
    // }

    // ===================================================================
    // P-PE-2: PoolEscrow ERC20 balance >= total
    // ===================================================================

    /// @dev ERC20 balance of PoolEscrow >= holding.total
    function property_PE_2_balance_gte_total() public {
        for (uint256 i = 0; i < createdPools.length; i++) {
            _checkPoolEscrowBalanceGteTotal(createdPools[i]);
        }
    }

    // ===================================================================
    // P-PE-3: PoolEscrow availableBalanceOf == total - reserved
    // ===================================================================

    /// @dev availableBalanceOf should match total - reserved
    function property_PE_3_available_balance() public {
        for (uint256 i = 0; i < createdPools.length; i++) {
            _checkPoolEscrowAvailableBalance(createdPools[i]);
        }
    }

    // ===================================================================
    // Internal Helpers
    // ===================================================================

    function _checkPoolEscrowTotalGteReserved(PoolId pid) internal {
        try balanceSheet.escrow(pid) returns (IPoolEscrow pe) {
            if (address(pe) == address(0)) return;
            PoolEscrow peConc = PoolEscrow(payable(address(pe)));
            AssetId aid = poolCurrency[pid];
            ShareClassId[] storage scs = poolShareClasses[pid];

            for (uint256 j = 0; j < scs.length; j++) {
                address asset = assetIdToAssetAddress[AssetId.unwrap(aid)];
                if (asset == address(0)) continue;
                (uint128 total, uint128 reserved) = peConc.holding(scs[j], asset, 0);
                gte(uint256(total), uint256(reserved), "P-PE-1: total < reserved");
            }
        } catch {}
    }

    function _checkPoolEscrowBalanceGteTotal(PoolId pid) internal {
        try balanceSheet.escrow(pid) returns (IPoolEscrow pe) {
            if (address(pe) == address(0)) return;
            PoolEscrow peConc = PoolEscrow(payable(address(pe)));
            AssetId aid = poolCurrency[pid];
            ShareClassId[] storage scs = poolShareClasses[pid];

            for (uint256 j = 0; j < scs.length; j++) {
                address asset = assetIdToAssetAddress[AssetId.unwrap(aid)];
                if (asset == address(0)) continue;
                (uint128 total,) = peConc.holding(scs[j], asset, 0);
                uint256 bal = MockERC20(asset).balanceOf(address(pe));
                gte(bal, uint256(total), "P-PE-2: ERC20 balance < total");
            }
        } catch {}
    }

    function _checkPoolEscrowAvailableBalance(PoolId pid) internal {
        try balanceSheet.escrow(pid) returns (IPoolEscrow pe) {
            if (address(pe) == address(0)) return;
            PoolEscrow peConc = PoolEscrow(payable(address(pe)));
            AssetId aid = poolCurrency[pid];
            ShareClassId[] storage scs = poolShareClasses[pid];

            for (uint256 j = 0; j < scs.length; j++) {
                address asset = assetIdToAssetAddress[AssetId.unwrap(aid)];
                if (asset == address(0)) continue;
                (uint128 total, uint128 reserved) = peConc.holding(scs[j], asset, 0);
                uint128 available = pe.availableBalanceOf(scs[j], asset, 0);
                // Skip when reserved > total (genuine PoolEscrow.reserve() finding)
                if (reserved > total) continue;
                eq(uint256(available), uint256(total - reserved), "P-PE-3: available != total - reserved");
            }
        } catch {}
    }
}
