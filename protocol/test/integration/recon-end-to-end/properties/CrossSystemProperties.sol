// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Asserts} from "@chimera/Asserts.sol";
import {MockERC20} from "@recon/MockERC20.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {AccountId} from "src/core/types/AccountId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {D18} from "src/misc/types/D18.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";

// Contracts
import {ShareToken} from "src/core/spoke/ShareToken.sol";
import {PoolEscrow} from "src/core/spoke/PoolEscrow.sol";
import {IPoolEscrow} from "src/core/spoke/interfaces/IPoolEscrow.sol";

import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title CrossSystemProperties
/// @notice Hub↔Spoke cross-system invariants (P-CS-1~7).
///         These are the KEY properties that can ONLY be verified in E2E mode
///         (not in isolated hub/spoke suites).
abstract contract CrossSystemProperties is BeforeAfter, Asserts {
    // ===================================================================
    // P-CS-1: Hub-Spoke Deposit Consistency
    // ===================================================================

    /// @dev Hub pendingDeposit (BRM) >= sum of per-user pending deposit requests.
    ///      This invariant only holds when no approval has ever happened (all epochs == 1),
    ///      because approveDeposits reduces pendingDeposit but individual depositRequest.pending
    ///      is only reduced during claim (notifyDeposit). After any approval, the aggregate
    ///      and individual counters diverge permanently until all users claim.
    function property_CS_1_deposit_consistency() public {
        if (createdPools.length == 0 || address(vault) == address(0)) return;

        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId pid = createdPools[i];
            AssetId aid = poolCurrency[pid];
            ShareClassId[] storage scs = poolShareClasses[pid];

            for (uint256 j = 0; j < scs.length; j++) {
                // Only valid before first approval (raw epochs start at 0)
                (uint32 dEp, uint32 iEp,,) = brm.epochId(pid, scs[j], aid);
                if (dEp > 0 || iEp > 0) continue;

                uint128 hubPending = brm.pendingDeposit(pid, scs[j], aid);

                uint128 hubUserSum = 0;
                address[] memory actors = _getActors();
                for (uint256 k = 0; k < actors.length; k++) {
                    (uint128 pending,) = brm.depositRequest(pid, scs[j], aid, CastLib.toBytes32(actors[k]));
                    hubUserSum += pending;
                }

                gte(uint256(hubPending), uint256(hubUserSum), "P-CS-1: pendingDeposit < sum(userRequests)");
            }
        }
    }

    // ===================================================================
    // P-CS-2: Share Issuance Balance
    // ===================================================================

    /// @dev Spoke totalSupply >= Hub totalIssuance.
    ///      Spoke is always >= Hub because BalanceSheet.issue() mints shares immediately,
    ///      but Hub only learns about issuance when submitQueuedShares() sends the message back.
    ///      After submitQueuedShares, they should match (with synchronous messaging).
    function property_CS_2_share_issuance_balance() public {
        if (createdPools.length == 0) return;

        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId pid = createdPools[i];
            ShareClassId[] storage scs = poolShareClasses[pid];

            for (uint256 j = 0; j < scs.length; j++) {
                uint128 hubIssuance = shareClassManager.totalIssuance(pid, scs[j]);
                address tokenAddr = address(spoke.shareToken(pid, scs[j]));
                if (tokenAddr == address(0)) continue;

                uint256 spokeSupply = ShareToken(tokenAddr).totalSupply();

                // Spoke is always ahead or equal (shares minted before Hub is notified)
                gte(spokeSupply, uint256(hubIssuance), "P-CS-2: spoke totalSupply < hub issuance");
            }
        }
    }

    // ===================================================================
    // P-CS-3: Escrow Solvency Chain
    // ===================================================================

    /// @dev GlobalEscrow asset balance >= sum of user maxWithdraw
    ///      PoolEscrow.total >= PoolEscrow.reserved
    function property_CS_3_escrow_solvency() public {
        if (address(vault) == address(0)) return;

        // Part A: Global escrow solvency
        address assetAddr = vault.asset();
        uint256 escrowBalance = MockERC20(assetAddr).balanceOf(address(escrow));
        uint256 sumMaxWithdraw = 0;

        address[] memory actors = _getActors();
        for (uint256 k = 0; k < actors.length; k++) {
            sumMaxWithdraw += vault.maxWithdraw(actors[k]);
        }

        gte(escrowBalance, sumMaxWithdraw, "P-CS-3a: escrow balance < sum(maxWithdraw)");

        // Part B: PoolEscrow solvency
        for (uint256 i = 0; i < createdPools.length; i++) {
            try balanceSheet.escrow(createdPools[i]) returns (IPoolEscrow pe) {
                if (address(pe) == address(0)) continue;
                AssetId aid = poolCurrency[createdPools[i]];
                ShareClassId[] storage scs = poolShareClasses[createdPools[i]];

                PoolEscrow peConc = PoolEscrow(payable(address(pe)));
                for (uint256 j = 0; j < scs.length; j++) {
                    address asset = assetIdToAssetAddress[AssetId.unwrap(aid)];
                    if (asset == address(0)) continue;
                    (uint128 total, uint128 reserved) = peConc.holding(scs[j], asset, 0);
                    gte(uint256(total), uint256(reserved), "P-CS-3b: PE total < PE reserved");
                }
            } catch {}
        }
    }

    // ===================================================================
    // P-CS-4: Price Propagation Consistency
    // ===================================================================

    /// @dev Hub pricePoolPerAsset == Spoke pricePoolPerAsset (when both are set).
    ///      Prices are only propagated to Spoke via explicit updatePricePoolPerAsset call.
    ///      Skip comparison when Spoke price is 0 (not yet propagated).
    function property_CS_4_price_propagation() public {
        if (createdPools.length == 0) return;

        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId pid = createdPools[i];
            AssetId aid = poolCurrency[pid];
            ShareClassId[] storage scs = poolShareClasses[pid];

            for (uint256 j = 0; j < scs.length; j++) {
                try hub.pricePoolPerAsset(pid, scs[j], aid) returns (D18 hubPrice) {
                    try spoke.pricePoolPerAsset(pid, scs[j], aid, false) returns (D18 spokePrice) {
                        // Only compare when Spoke price has been propagated
                        if (D18.unwrap(spokePrice) == 0) continue;
                        eq(
                            D18.unwrap(hubPrice),
                            D18.unwrap(spokePrice),
                            "P-CS-4: hub price != spoke price"
                        );
                    } catch {}
                } catch {}
            }
        }
    }

    // ===================================================================
    // P-CS-5: BRM Epoch Monotonicity
    // ===================================================================

    /// @dev depositEpoch >= issueEpoch, redeemEpoch >= revokeEpoch
    function property_CS_5_epoch_monotonicity() public {
        if (createdPools.length == 0) return;

        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId pid = createdPools[i];
            AssetId aid = poolCurrency[pid];
            ShareClassId[] storage scs = poolShareClasses[pid];

            for (uint256 j = 0; j < scs.length; j++) {
                (uint32 dEp, uint32 iEp, uint32 rEp, uint32 rvEp) = brm.epochId(pid, scs[j], aid);

                gte(uint256(dEp), uint256(iEp), "P-CS-5a: depositEpoch < issueEpoch");
                gte(uint256(rEp), uint256(rvEp), "P-CS-5b: redeemEpoch < revokeEpoch");
            }
        }
    }

    // ===================================================================
    // P-CS-6: Share Token Conservation
    // ===================================================================

    /// @dev totalSupply >= sum of all tracked holder balances
    function property_CS_6_share_token_conservation() public {
        if (address(token) == address(0)) return;

        uint256 totalSupply = token.totalSupply();
        uint256 sumBalances = 0;

        address[] memory actors = _getActors();
        for (uint256 k = 0; k < actors.length; k++) {
            sumBalances += token.balanceOf(actors[k]);
        }
        sumBalances += token.balanceOf(address(escrow));
        sumBalances += token.balanceOf(address(this));

        try balanceSheet.escrow(activePoolId) returns (IPoolEscrow pe) {
            if (address(pe) != address(0)) {
                sumBalances += token.balanceOf(address(pe));
            }
        } catch {}

        gte(totalSupply, sumBalances, "P-CS-6: totalSupply < sum(balances)");
    }

    // ===================================================================
    // P-CS-7: Queue Sync Completeness
    // ===================================================================

    /// @dev After BS_SUBMIT_QUEUED_ASSETS: queuedAssets deposits and withdrawals should be 0
    function property_CS_7_queue_sync_completeness() public {
        if (currentOperation != OpType.BS_SUBMIT_QUEUED_ASSETS) return;
        if (createdPools.length == 0) return;

        PoolId pid = activePoolId;
        AssetId aid = activeAssetId;
        ShareClassId[] storage scs = poolShareClasses[pid];

        for (uint256 j = 0; j < scs.length; j++) {
            (uint128 deposits, uint128 withdrawals) = balanceSheet.queuedAssets(pid, scs[j], aid);
            eq(uint256(deposits), 0, "P-CS-7a: queuedAssets.deposits != 0 after submit");
            eq(uint256(withdrawals), 0, "P-CS-7b: queuedAssets.withdrawals != 0 after submit");
        }
    }

    // ===================================================================
    // P-CS-8: NAV Accounting Consistency
    // ===================================================================

    /// @dev navManager.netAssetValue == equity + gain - loss - liability (from accounting)
    function property_CS_8_nav_accounting_consistency() public {
        if (createdPools.length == 0) return;

        for (uint256 i = 0; i < createdPools.length; i++) {
            _checkNAVConsistency(createdPools[i]);
        }
    }

    function _checkNAVConsistency(PoolId pid) internal {
        try navManager.netAssetValue(pid, SPOKE_CENTRIFUGE_ID) returns (uint128 navVal) {
            AccountId equityAccId = navManager.equityAccount(SPOKE_CENTRIFUGE_ID);
            (,,, uint64 eqUpdated,) = accounting.accounts(pid, equityAccId);
            if (eqUpdated == 0) return;

            uint128 manualNAV = _computeManualNAV(pid);
            eq(uint256(navVal), uint256(manualNAV), "P-CS-8: NAV != manual calculation");
        } catch {}
    }

    function _computeManualNAV(PoolId pid) internal view returns (uint128) {
        (bool eqPos, uint128 eqVal) = accounting.accountValue(pid, navManager.equityAccount(SPOKE_CENTRIFUGE_ID));
        (bool gnPos, uint128 gnVal) = accounting.accountValue(pid, navManager.gainAccount(SPOKE_CENTRIFUGE_ID));
        (bool lsPos, uint128 lsVal) = accounting.accountValue(pid, navManager.lossAccount(SPOKE_CENTRIFUGE_ID));
        (bool liPos, uint128 liVal) = accounting.accountValue(pid, navManager.liabilityAccount(SPOKE_CENTRIFUGE_ID));

        uint128 pos = 0;
        uint128 neg = 0;
        if (eqPos) pos += eqVal; else neg += eqVal;
        if (gnPos) pos += gnVal; else neg += gnVal;
        if (lsPos) neg += lsVal; else pos += lsVal;
        if (liPos) neg += liVal; else pos += liVal;

        return neg >= pos ? 0 : pos - neg;
    }

    // ===================================================================
    // P-CS-9: Accounting Equation
    // ===================================================================

    /// @dev For each holding: asset + loss == equity + gain (within 1 wei)
    function property_CS_9_accounting_equation() public {
        if (createdPools.length == 0) return;

        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId pid = createdPools[i];
            AssetId aid = poolCurrency[pid];
            ShareClassId[] storage scs = poolShareClasses[pid];

            for (uint256 j = 0; j < scs.length; j++) {
                AccountId assetAccId = holdings.accountId(pid, scs[j], aid, 0);
                AccountId equityAccId = holdings.accountId(pid, scs[j], aid, 1);
                AccountId gainAccId = holdings.accountId(pid, scs[j], aid, 2);
                AccountId lossAccId = holdings.accountId(pid, scs[j], aid, 3);

                (,,, uint64 assetUpdated,) = accounting.accounts(pid, assetAccId);
                if (assetUpdated == 0) continue;

                (, uint128 assetVal) = accounting.accountValue(pid, assetAccId);
                (, uint128 equityVal) = accounting.accountValue(pid, equityAccId);
                (, uint128 gainVal) = accounting.accountValue(pid, gainAccId);
                (, uint128 lossVal) = accounting.accountValue(pid, lossAccId);

                uint256 lhs = uint256(assetVal) + uint256(lossVal);
                uint256 rhs = uint256(equityVal) + uint256(gainVal);
                uint256 diff = lhs > rhs ? lhs - rhs : rhs - lhs;

                lte(diff, 1, "P-CS-7: accounting equation violated (>1 wei)");
            }
        }
    }
}
