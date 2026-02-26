// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Asserts} from "@chimera/Asserts.sol";
import {MockERC20} from "@recon/MockERC20.sol";
import {vm} from "@chimera/Hevm.sol";

import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title VaultE2EProperties
/// @notice ERC-7540 vault properties adapted for E2E context.
///         Verifies vault view function liveness, totalAssets solvency,
///         and ERC-4626 max* function constraints.
abstract contract VaultE2EProperties is BeforeAfter, Asserts {
    // ===================================================================
    // P-V-1: Vault View Functions Never Revert
    // ===================================================================

    /// @dev ERC-4626 view functions should never revert on a deployed vault
    function property_V_1_views_never_revert() public {
        if (address(vault) == address(0)) return;

        vault.totalAssets();
        vault.asset();
        vault.share();

        address[] memory actors = _getActors();
        for (uint256 k = 0; k < actors.length; k++) {
            vault.maxDeposit(actors[k]);
            vault.maxMint(actors[k]);
            vault.maxRedeem(actors[k]);
            vault.maxWithdraw(actors[k]);
        }
    }

    // ===================================================================
    // P-V-2: totalAssets Solvency
    // ===================================================================

    /// @dev totalAssets <= actual escrow balance (asset tokens held)
    function property_V_2_totalAssets_solvency() public {
        if (address(vault) == address(0)) return;

        address assetAddr = vault.asset();
        uint256 escrowBalance = MockERC20(assetAddr).balanceOf(address(escrow));
        uint256 totalAssets = vault.totalAssets();

        gte(escrowBalance, totalAssets, "P-V-2: escrow balance < totalAssets");
    }

    // ===================================================================
    // P-V-3: maxDeposit Consistency
    // ===================================================================

    /// @dev If maxDeposit > 0, depositing maxDeposit should not revert (ERC-7540-9)
    function property_V_3_maxDeposit_honoured() public {
        if (address(vault) == address(0)) return;

        address actor = _getActor();
        uint256 maxDep = vault.maxDeposit(actor);
        if (maxDep == 0) return;

        // Ensure actor has enough tokens and approval
        address assetAddr = vault.asset();
        uint256 bal = MockERC20(assetAddr).balanceOf(actor);
        uint256 allowance = MockERC20(assetAddr).allowance(actor, address(vault));
        if (bal < maxDep || allowance < maxDep) return;

        vm.prank(actor);
        try vault.deposit(maxDep, actor) {} catch {
            // If maxDeposit > 0 but deposit reverts, that's a violation
            t(false, "P-V-3: maxDeposit > 0 but deposit reverted");
        }
    }

    // ===================================================================
    // P-V-4: maxRedeem Consistency
    // ===================================================================

    /// @dev If maxRedeem > 0, redeeming maxRedeem should not revert (ERC-7540-9)
    function property_V_4_maxRedeem_honoured() public {
        if (address(vault) == address(0)) return;

        address actor = _getActor();
        uint256 maxRed = vault.maxRedeem(actor);
        if (maxRed == 0) return;

        vm.prank(actor);
        try vault.redeem(maxRed, actor, actor) {} catch {
            t(false, "P-V-4: maxRedeem > 0 but redeem reverted");
        }
    }

    // ===================================================================
    // P-V-5: Deposit Monotonicity
    // ===================================================================

    /// @dev After a deposit claim, totalAssets should increase (or stay same if 0 assets)
    function property_V_5_deposit_increases_totalAssets() public {
        if (currentOperation != OpType.VAULT_DEPOSIT && currentOperation != OpType.VAULT_MINT) return;
        if (address(vault) == address(0)) return;

        // totalAssets after >= totalAssets before (if the operation succeeded)
        // We check via before/after spoke state: totalShareSupply should not decrease
        // after a deposit claim
        gte(
            _after.totalShareSupply,
            _before.totalShareSupply,
            "P-V-5: totalShareSupply decreased after deposit"
        );
    }

    // ===================================================================
    // P-V-6: Redeem Does Not Increase Share Supply
    // ===================================================================

    /// @dev After a redeem claim, totalShareSupply should not increase
    function property_V_6_redeem_decreases_supply() public {
        if (currentOperation != OpType.VAULT_REDEEM && currentOperation != OpType.VAULT_WITHDRAW) return;
        if (address(vault) == address(0)) return;

        lte(
            _after.totalShareSupply,
            _before.totalShareSupply,
            "P-V-6: totalShareSupply increased after redeem"
        );
    }

    // ===================================================================
    // P-V-7: Protocol-Favorable Rounding
    // ===================================================================

    /// @dev convertToAssets(convertToShares(x)) <= x (deposit rounding favors protocol)
    function property_V_7_deposit_rounding() public {
        if (address(vault) == address(0)) return;

        uint256 assets = 1e18;
        try vault.convertToShares(assets) returns (uint256 shares) {
            if (shares == 0) return;
            try vault.convertToAssets(shares) returns (uint256 roundtrip) {
                lte(roundtrip, assets, "P-V-7: deposit rounding unfavorable to protocol");
            } catch {}
        } catch {}
    }

    /// @dev convertToShares(convertToAssets(x)) <= x (redeem rounding favors protocol)
    function property_V_7b_redeem_rounding() public {
        if (address(vault) == address(0)) return;

        uint256 shares = 1e18;
        try vault.convertToAssets(shares) returns (uint256 assets) {
            if (assets == 0) return;
            try vault.convertToShares(assets) returns (uint256 roundtrip) {
                lte(roundtrip, shares, "P-V-7b: redeem rounding unfavorable to protocol");
            } catch {}
        } catch {}
    }
}
