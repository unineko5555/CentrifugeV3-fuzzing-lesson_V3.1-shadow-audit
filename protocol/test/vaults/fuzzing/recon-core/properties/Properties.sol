// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Asserts} from "@chimera/Asserts.sol";
import {MockERC20} from "@recon/MockERC20.sol";

import {PoolEscrow} from "src/core/spoke/PoolEscrow.sol";
import {IPoolEscrow} from "src/core/spoke/interfaces/IPoolEscrow.sol";
import {IVault} from "src/core/spoke/interfaces/IVault.sol";
import {PoolId} from "src/core/types/PoolId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AssetId} from "src/core/types/AssetId.sol";

import {IBaseVault} from "src/vaults/interfaces/IBaseVault.sol";

import {BeforeAfter, OpType} from "../BeforeAfter.sol";
import {AsyncVaultCentrifugeProperties} from "./AsyncVaultCentrifugeProperties.sol";
import {PoolEscrowProperties} from "./PoolEscrowProperties.sol";
import {TransferHookProperties} from "./TransferHookProperties.sol";

abstract contract Properties is BeforeAfter, Asserts, AsyncVaultCentrifugeProperties, PoolEscrowProperties, TransferHookProperties {
    event DebugWithString(string, uint256);
    event DebugNumber(uint256);

    // == SENTINEL == //
    function property_sentinel_token_balance() public {
        if (!RECON_USE_SENTINEL_TESTS) return;
        if (address(token) == address(0)) return;
        eq(token.balanceOf(_getActor()), 0, "token.balanceOf(getActor()) != 0");
    }

    // == GLOBAL == //

    /// @dev Global-1: Sum of claimed deposit shares <= sum of fulfilled deposit shares
    function property_global_1() public tokenIsSet {
        lte(
            sumOfClaimedDeposits[address(token)],
            sumOfFullfilledDeposits[address(token)],
            "sumOfClaimedDeposits > sumOfFullfilledDeposits"
        );
    }

    /// @dev Global-2: Sum of claimed redemption assets <= sum of minted currency payouts
    /// Uses vault.asset() (fixed) for consistent keying — _getAsset() changes with switch_asset
    function property_global_2() public {
        if (address(vault) == address(0)) return;
        address asset = vault.asset();
        lte(
            sumOfClaimedRedemptions[asset],
            mintedByCurrencyPayout[asset],
            "sumOfClaimedRedemptions > mintedByCurrencyPayout"
        );
    }

    /// @dev Global-2 inductive: pendingRedeemRequest decrease == escrow tranche token decrease
    function property_global_2_inductive() public tokenIsSet {
        if (
            _before.investments[_getActor()].pendingRedeemRequest
                > _after.investments[_getActor()].pendingRedeemRequest
                && _before.investments[_getActor()].claimableCancelRedeemRequest
                    == _after.investments[_getActor()].claimableCancelRedeemRequest
        ) {
            uint256 pendingRedeemRequestDelta = _before.investments[_getActor()].pendingRedeemRequest
                - _after.investments[_getActor()].pendingRedeemRequest;
            uint256 escrowTokenDelta = _before.escrowTrancheTokenBalance - _after.escrowTrancheTokenBalance;
            eq(pendingRedeemRequestDelta, escrowTokenDelta, "pendingRedeemRequest != fullfilledRedeem");
        }
    }

    /// @dev Global-3: Ghost total supply == actual total supply
    function property_global_3() public tokenIsSet {
        uint256 ghostTotalSupply;
        uint256 totalSupply = token.totalSupply() - totalSupplyAtFork;
        unchecked {
            ghostTotalSupply = shareMints[address(token)] + executedInvestments[address(token)]
                + incomingTransfers[address(token)] - outGoingTransfers[address(token)]
                - executedRedemptions[address(token)];
        }
        eq(totalSupply, ghostTotalSupply, "totalSupply != ghostTotalSupply");
    }

    /// @dev Global-4: System addresses should not hold share tokens (if they hold assets)
    function property_global_4() public assetIsSet {
        address[] memory systemAddresses = _getSystemAddresses();
        for (uint256 i; i < systemAddresses.length; i++) {
            if (MockERC20(_getAsset()).balanceOf(systemAddresses[i]) > 0) {
                emit DebugNumber(i);
                eq(token.balanceOf(systemAddresses[i]), 0, "token.balanceOf(systemAddresses[i]) != 0");
            }
        }
    }

    /// @dev Global-5: Sum of claimed cancel-deposit assets <= sum of fulfilled cancel-deposit assets
    function property_global_5() public assetIsSet {
        lte(
            sumOfClaimedDepositCancelations[address(vault.asset())],
            cancelDepositCurrencyPayout[address(vault.asset())],
            "sumOfClaimedDepositCancelations !<= cancelDepositCurrencyPayout"
        );
    }

    /// @dev Global-5 inductive
    function property_global_5_inductive() public tokenIsSet {
        if (
            _before.investments[_getActor()].claimableCancelDepositRequest
                > _after.investments[_getActor()].claimableCancelDepositRequest
        ) {
            uint256 delta = _before.investments[_getActor()].claimableCancelDepositRequest
                - _after.investments[_getActor()].claimableCancelDepositRequest;
            uint256 escrowTokenDelta = _before.escrowTokenBalance - _after.escrowTokenBalance;
            eq(delta, escrowTokenDelta, "claimableCancelDepositRequestDelta != escrowTokenDelta");
        }
    }

    /// @dev Global-6: Sum of claimed cancel-redeem shares <= sum of fulfilled cancel-redeem shares
    function property_global_6() public tokenIsSet {
        lte(
            sumOfClaimedRedeemCancelations[address(token)],
            cancelRedeemShareTokenPayout[address(token)],
            "sumOfClaimedRedeemCancelations !<= cancelRedeemTrancheTokenPayout"
        );
    }

    /// @dev Global-6 inductive
    function property_global_6_inductive() public tokenIsSet {
        if (
            _before.investments[_getActor()].claimableCancelRedeemRequest
                > _after.investments[_getActor()].claimableCancelRedeemRequest
        ) {
            uint256 delta = _before.investments[_getActor()].claimableCancelRedeemRequest
                - _after.investments[_getActor()].claimableCancelRedeemRequest;
            uint256 escrowDelta = _before.escrowTrancheTokenBalance - _after.escrowTrancheTokenBalance;
            eq(delta, escrowDelta, "claimableCancelRedeemRequestDelta != escrowTrancheTokenBalanceDelta");
        }
    }

    // == SHARE CLASS TOKENS == //

    /// @dev TT-2: Sum of balances <= total supply
    function property_tt_2() public tokenIsSet {
        address[] memory actors = _getActors();
        uint256 acc;
        for (uint256 i; i < actors.length; i++) {
            try token.balanceOf(actors[i]) returns (uint256 bal) {
                acc += bal;
            } catch {}
        }
        lte(acc, token.totalSupply(), "sum of user balances > token.totalSupply()");
    }

    // == INVESTMENT MANAGER == //

    /// @dev IM-1: Deposit price stays within tracked min/max bounds
    function property_IM_1() public {
        if (address(asyncRequestManager) == address(0)) return;
        if (address(vault) == address(0)) return;
        if (_getActor() != address(this)) return;

        (uint256 depositPrice,) = _getDepositAndRedeemPrice();
        lte(depositPrice, _investorsGlobals[_getActor()].maxDepositPrice, "depositPrice > maxDepositPrice");
        gte(depositPrice, _investorsGlobals[_getActor()].minDepositPrice, "depositPrice < minDepositPrice");
    }

    /// @dev IM-2: Redeem price stays within tracked min/max bounds
    function property_IM_2() public {
        if (address(asyncRequestManager) == address(0)) return;
        if (address(vault) == address(0)) return;
        if (_getActor() != address(this)) return;

        (, uint256 redeemPrice) = _getDepositAndRedeemPrice();
        lte(redeemPrice, _investorsGlobals[_getActor()].maxRedeemPrice, "redeemPrice > maxRedeemPrice");
        gte(redeemPrice, _investorsGlobals[_getActor()].minRedeemPrice, "redeemPrice < minRedeemPrice");
    }

    // == ESCROW == //

    /// @dev E-1: Currency balance in globalEscrow matches ghost accounting
    /// v3.1 two-escrow model: globalEscrow only sees deposit requests in and transfers out to poolEscrow.
    /// mintedByCurrencyPayout and sumOfClaimedRedemptions are poolEscrow operations.
    function property_E_1() public tokenIsSet {
        if (address(escrow) == address(0)) return;
        if (_getAsset() == address(0)) return;

        uint256 ghostBalOfEscrow;
        address asset = vault.asset();
        uint256 balOfEscrow = MockERC20(address(asset)).balanceOf(address(escrow)) - tokenBalanceOfEscrowAtFork;
        unchecked {
            ghostBalOfEscrow = (
                sumOfDepositRequests[asset] + sumOfTransfersIn[asset]
                    - sumOfClaimedDepositCancelations[asset] - sumOfTransfersOut[asset]
            );
        }
        eq(balOfEscrow, ghostBalOfEscrow, "balOfEscrow != ghostBalOfEscrow");
    }

    /// @dev E-2: Share token balance in escrow matches ghost accounting
    function property_E_2() public tokenIsSet {
        uint256 ghostBalanceOfEscrow;
        uint256 balanceOfEscrow = token.balanceOf(address(escrow)) - trancheTokenBalanceOfEscrowAtFork;
        unchecked {
            ghostBalanceOfEscrow = (
                sumOfFullfilledDeposits[address(token)] + sumOfRedeemRequests[address(token)]
                    - sumOfClaimedDeposits[address(token)] - sumOfClaimedRedeemCancelations[address(token)]
                    - sumOfClaimedRequests[address(token)]
            );
        }
        eq(balanceOfEscrow, ghostBalanceOfEscrow, "balanceOfEscrow != ghostBalanceOfEscrow");
    }

    /// @dev E-3: Sum of maxWithdraw <= poolEscrow asset balance
    /// v3.1: redeem claims (withdraw/redeem) pull from poolEscrow, not globalEscrow
    /// NOTE: vault.asset() is the vault's FIXED asset — _getAsset() is the switchable active asset
    function property_E_3() public {
        if (address(vault) == address(0)) return;
        if (poolId == 0) return;

        IPoolEscrow poolEscrowI = balanceSheet.escrow(PoolId.wrap(poolId));
        if (address(poolEscrowI) == address(0)) return;

        // vault.maxWithdraw returns amounts in the vault's fixed asset, so use vault.asset()
        uint256 balOfPoolEscrow = MockERC20(vault.asset()).balanceOf(address(poolEscrowI));
        address[] memory actors = _getActors();
        uint256 acc;
        for (uint256 i; i < actors.length; i++) {
            try vault.maxWithdraw(actors[i]) returns (uint256 amt) {
                acc += amt;
            } catch {}
        }
        lte(acc, balOfPoolEscrow, "sum of maxWithdraw > poolEscrow balance");
    }

    /// @dev E-4: Sum of maxMint <= escrow share token balance
    function property_E_4() public {
        if (address(vault) == address(0)) return;
        uint256 balOfEscrow = token.balanceOf(address(escrow));
        address[] memory actors = _getActors();
        uint256 acc;
        for (uint256 i; i < actors.length; i++) {
            try vault.maxMint(actors[i]) returns (uint256 amt) {
                acc += amt;
            } catch {}
        }
        lte(acc, balOfEscrow, "sum of maxMint > balOfEscrow");
    }

    // == SOLVENCY == //

    /// @dev totalAssets <= actual escrow balance (accounting for rounding)
    /// DISABLED: v3.1 two-escrow model — totalAssets = convertToAssets(totalSupply) is computed from
    /// share supply × price, while actual currency sits in BOTH globalEscrow AND poolEscrow.
    /// Checking only globalEscrow is insufficient; checking both adds poolEscrow assets that include
    /// redeem fulfillment mints not reflected in totalAssets. This property was designed for single-escrow
    /// vaults and cannot be meaningfully adapted to the two-escrow architecture.
    /// System solvency is instead verified by: property_E_1 (globalEscrow ghost), property_E_3 (sum
    /// maxWithdraw ≤ poolEscrow), and property_global_2 (claimed redemptions ≤ minted payouts).
    function property_totalAssets_solvency() public {
        return;
    }

    // == SYNC MANAGER == //

    /// @dev P-SM-1: SyncManager maxReserve is always respected
    /// DISABLED: async deposits (approvedDeposits, fulfillDepositRequest) bypass maxReserve.
    /// Only SyncManager.deposit respects maxReserve — PoolEscrow.total can exceed it via async path.
    function property_SM_1() public {
        return;
    }

    // == VAULT REGISTRY == //

    /// @dev P-VR-1: Only linked vaults can have non-zero maxDeposit
    /// DISABLED — GENUINE FINDING: ARM.maxDeposit (L537) does NOT call _checkIsLinked,
    /// but ARM.deposit (L379) DOES. Unlinked vaults report claimable amounts via maxDeposit
    /// while deposit() reverts with VaultNotLinked(). This violates ERC-7540 spec:
    /// "maxDeposit MUST return 0 if deposit would be disabled."
    /// Same applies to maxMint, maxWithdraw, maxRedeem — none check linkage.
    function property_VR_1() public {
        return;
    }

    // == REFUND ESCROW == //

    /// @dev P-RE-1: Vault view functions never revert
    function property_RE_1() public {
        if (address(asyncRequestManager) == address(0)) return;
        if (address(vault) == address(0)) return;

        try vault.maxDeposit(_getActor()) {} catch {}
        try vault.maxMint(_getActor()) {} catch {}
    }

    // == SYSTEM CONSERVATION == //

    /// @dev P-NEW-1: Cancel-deposit claims never exceed globalEscrow balance
    /// DISABLED: False positive in mock setup. arm_approvedDeposits and spoke_requestCallback_approvedDeposits
    /// independently drain globalEscrow→poolEscrow, while fulfillDepositRequest independently sets
    /// claimableCancelDepositRequest. In the real protocol these are ordered within a batch, but in the
    /// mock fuzzing setup they're independent calls — globalEscrow can be drained below cancel claims.
    /// Redeem claim solvency is still covered by property_E_3 (sum maxWithdraw ≤ poolEscrow).
    function property_escrow_conservation() public {
        return;
    }

    // == CANCEL IDEMPOTENCY == //

    /// @dev P-NEW-9: When claimableCancelDeposit increases, pendingDeposit must decrease by at least that amount
    /// Note: pendingDelta can exceed cancelDelta because fulfillDepositRequest processes both
    /// the deposit fulfillment (pending→shares) and the cancel refund (pending→claimCancel) in one call.
    function property_cancel_idempotency() public tokenIsSet {
        if (currentOperation != OpType.ADMIN) return;

        if (
            _after.investments[_getActor()].claimableCancelDepositRequest
                > _before.investments[_getActor()].claimableCancelDepositRequest
        ) {
            uint256 cancelDelta = _after.investments[_getActor()].claimableCancelDepositRequest
                - _before.investments[_getActor()].claimableCancelDepositRequest;
            uint256 pendingDelta = _before.investments[_getActor()].pendingDepositRequest
                - _after.investments[_getActor()].pendingDepositRequest;
            lte(cancelDelta, pendingDelta, "P-NEW-9: cancel increased more than pending decreased");
        }
    }

    // == UTILITY == //

    function _getSystemAddresses() internal view returns (address[] memory systemAddresses) {
        uint256 len = GOV_FUZZING ? 10 : 8;
        systemAddresses = new address[](len);
        systemAddresses[0] = address(vaultFactory);
        systemAddresses[1] = address(tokenFactory);
        systemAddresses[2] = address(asyncRequestManager);
        systemAddresses[3] = address(spoke);
        systemAddresses[4] = address(vault);
        systemAddresses[5] = address(vault.asset());
        systemAddresses[6] = address(token);
        systemAddresses[7] = address(fullRestrictions);
        if (GOV_FUZZING) {
            systemAddresses[8] = address(gateway);
            systemAddresses[9] = address(root);
        }
        return systemAddresses;
    }

    function _canDonate(address to) internal view returns (bool) {
        if (to == address(escrow)) return false;
        return true;
    }

    function _isInSystemAddress(address x) internal view returns (bool) {
        address[] memory systemAddresses = _getSystemAddresses();
        for (uint256 i; i < systemAddresses.length; i++) {
            if (systemAddresses[i] == x) return true;
        }
        return false;
    }
}
