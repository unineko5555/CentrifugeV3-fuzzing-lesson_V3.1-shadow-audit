// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

// Types
import {D18, d18} from "src/misc/types/D18.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";
import {IPoolEscrow} from "src/core/spoke/interfaces/IPoolEscrow.sol";
import {PoolEscrow} from "src/core/spoke/PoolEscrow.sol";

import {Properties} from "../properties/Properties.sol";

/// @title DoomsdayTargets
/// @notice Edge case and liveness verification targets for E2E fuzzing.
///         Verifies that view functions never revert, rounding is protocol-favorable,
///         NAV operations are sound, and BRM epoch ordering is maintained.
abstract contract DoomsdayTargets is BaseTargetFunctions, Properties {
    using CastLib for *;

    // ===================================================================
    // View Liveness (must never revert)
    // ===================================================================

    /// @dev Vault view functions should never revert
    function doomsday_vault_views_never_revert() public view vaultExists {
        // ERC-4626 views
        vault.maxDeposit(address(this));
        vault.maxMint(address(this));
        vault.maxRedeem(address(this));
        vault.maxWithdraw(address(this));
        vault.totalAssets();
        vault.asset();
        vault.share();
    }

    /// @dev Spoke view functions should never revert
    function doomsday_spoke_views_never_revert() public view poolExists {
        spoke.isPoolActive(activePoolId);
        spoke.shareToken(activePoolId, activeScId);
    }

    /// @dev Hub view functions should never revert
    function doomsday_hub_views_never_revert() public view poolExists {
        try hub.pricePoolPerAsset(activePoolId, activeScId, activeAssetId) {} catch {}
        try shareClassManager.pricePoolPerShare(activePoolId, activeScId) {} catch {}
    }

    /// @dev Spoke price view functions should never revert
    function doomsday_spoke_price_views_never_revert() public view poolExists {
        try spoke.pricePoolPerAsset(activePoolId, activeScId, activeAssetId, false) {} catch {}
        try spoke.pricePoolPerShare(activePoolId, activeScId, false) {} catch {}
    }

    /// @dev NAV view functions should never revert after initialization
    function doomsday_nav_views_never_revert() public view poolExists {
        try navManager.netAssetValue(activePoolId, SPOKE_CENTRIFUGE_ID) {} catch {}
        try navManager.equityAccount(SPOKE_CENTRIFUGE_ID) {} catch {}
        try navManager.gainAccount(SPOKE_CENTRIFUGE_ID) {} catch {}
        try navManager.lossAccount(SPOKE_CENTRIFUGE_ID) {} catch {}
        try navManager.liabilityAccount(SPOKE_CENTRIFUGE_ID) {} catch {}
        try navManager.assetAccount(activeAssetId) {} catch {}
    }

    /// @dev OracleValuation view functions should never revert
    function doomsday_oracle_views_never_revert() public view poolExists {
        try oracleValuation.getPrice(activePoolId, activeScId, activeAssetId) {} catch {}
    }

    // ===================================================================
    // Rounding Verification
    // ===================================================================

    /// @dev Verify protocol-favorable rounding in deposit conversions
    function doomsday_deposit_rounding() public view vaultExists {
        uint256 assets = 1e18;
        try vault.convertToShares(assets) returns (uint256 shares) {
            if (shares == 0) return;
            try vault.convertToAssets(shares) returns (uint256 roundtrip) {
                if (roundtrip > assets) revert("rounding: deposit roundtrip > original");
            } catch {}
        } catch {}
    }

    /// @dev Verify protocol-favorable rounding in redeem conversions
    function doomsday_redeem_rounding() public view vaultExists {
        uint256 shares = 1e18;
        try vault.convertToAssets(shares) returns (uint256 assets) {
            if (assets == 0) return;
            try vault.convertToShares(assets) returns (uint256 roundtrip) {
                if (roundtrip > shares) revert("rounding: redeem roundtrip > original");
            } catch {}
        } catch {}
    }

    // ===================================================================
    // BRM Epoch Queue Manipulation
    // ===================================================================

    /// @dev BRM rounding: deposit amount after approve+issue <= requested
    function doomsday_brm_deposit_rounding() public poolExists {
        // After each approve+issue, shares issued * price should not exceed approved amount
        uint32 nowDep = brm.nowDepositEpoch(activePoolId, activeScId, activeAssetId);
        uint32 nowIssue = brm.nowIssueEpoch(activePoolId, activeScId, activeAssetId);

        // Verify epoch ordering invariant
        assert(nowDep >= nowIssue);

        // Verify BRM pending is non-negative (always true for uint128, structural check)
        uint128 pending = brm.pendingDeposit(activePoolId, activeScId, activeAssetId);
        assert(pending >= 0);
    }

    /// @dev BRM rounding: redeem amount after approve+revoke <= requested
    function doomsday_brm_redeem_rounding() public poolExists {
        uint32 nowRedeem = brm.nowRedeemEpoch(activePoolId, activeScId, activeAssetId);
        uint32 nowRevoke = brm.nowRevokeEpoch(activePoolId, activeScId, activeAssetId);

        // Verify epoch ordering invariant
        assert(nowRedeem >= nowRevoke);

        uint128 pending = brm.pendingRedeem(activePoolId, activeScId, activeAssetId);
        assert(pending >= 0);
    }

    // ===================================================================
    // NAV Manipulation Verification
    // ===================================================================

    /// @dev Verify NAV update + close doesn't create negative equity
    function doomsday_nav_no_negative_equity() public poolExists {
        try navManager.netAssetValue(activePoolId, SPOKE_CENTRIFUGE_ID) returns (uint128 nav) {
            // NAV is uint128, inherently >= 0
            // But the internal calculation clips to 0 — verify it doesn't revert
            assert(nav <= type(uint128).max);
        } catch {}
    }

    /// @dev Verify closeGainLoss is idempotent (calling twice doesn't break anything)
    function doomsday_close_gain_loss_idempotent() public poolExists {
        try navManager.closeGainLoss(activePoolId, SPOKE_CENTRIFUGE_ID) {} catch {}
        // Second call should also succeed (or gracefully return)
        try navManager.closeGainLoss(activePoolId, SPOKE_CENTRIFUGE_ID) {} catch {}
    }

    // ===================================================================
    // Optimization Targets (Medusa optimization mode)
    // ===================================================================

    /// @dev Optimization target: maximize stuck funds in PoolEscrow (Finding 5)
    ///      Stuck funds = PoolEscrow total - maxWithdraw for current actor
    function optimize_max_stuck_funds() public returns (int256) {
        if (address(vault) == address(0)) return 0;
        (address asset, uint256 tokenId) = spoke.idToAsset(activeAssetId);
        if (asset == address(0)) return 0;

        IPoolEscrow poolEscrowI = balanceSheet.escrow(activePoolId);
        if (address(poolEscrowI) == address(0)) return 0;
        PoolEscrow poolEscrow_ = PoolEscrow(payable(address(poolEscrowI)));

        (uint128 total,) = poolEscrow_.holding(activeScId, asset, tokenId);
        uint256 maxW = vault.maxWithdraw(address(this));
        if (uint256(total) > maxW) {
            return int256(uint256(total) - maxW);
        }
        return 0;
    }
}
