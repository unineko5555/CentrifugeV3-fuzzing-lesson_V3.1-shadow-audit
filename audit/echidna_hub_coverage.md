# Echidna Hub Coverage Analysis

## Overview

- Config: `echidna_hub.yaml` — Contract: `CryticPoolTester`, mode: assertion, seqLen: 200, testLimit: 100M
- LCOV: `echidna_hub/covered.1772013011.lcov` — 19,392 instrumented lines across 200+ files
- Corpus: 4 coverage sequences in `echidna_hub/coverage/`
- Reproducers: 11 failure sequences in `echidna_hub/reproducers/`

## Overall Coverage

| Scope | Lines Hit | Lines Total | Coverage |
| --- | --- | --- | --- |
| **All instrumented** | 1,537 | 19,392 | 7.9% |
| **src/hub/ (target module)** | 507 | 929 | **54.6%** |
| **src/ (all protocol)** | 607 | 4,373 | 13.9% |
| **test/hub/fuzzing/recon-hub/** | 770 | 3,478 | 22.1% |

The raw 7.9% is misleading — the hub suite intentionally targets only Hub-side contracts. Spoke, Vaults, common/Gateway, and all unit/integration test files are out of scope and correctly show 0% coverage.

## Module Breakdown

| Module | Hit/Total | Coverage | Notes |
| --- | --- | --- | --- |
| src/hub/ | 507/929 | **54.6%** | Primary target — Accounting, Holdings, Hub, ShareClassManager |
| src/misc/ | 65/438 | 14.8% | Libraries (MathLib, CastLib, D18) used by hub |
| src/common/ | 33/1,385 | 2.4% | Only Root, PricingLib, types — Gateway/MessageLib mocked |
| src/hooks/ | 1/177 | 0.6% | UpdateRestrictionMessageLib only |
| src/spoke/ | 1/594 | 0.2% | Intentionally out of scope (mocked) |
| src/vaults/ | 0/850 | 0.0% | Intentionally out of scope |

## Per-File Coverage (src/hub/ Target Files)

| File | Hit/Total | Coverage | Assessment |
| --- | --- | --- | --- |
| [Accounting.sol](src/hub/Accounting.sol) | 59/65 | **90.8%** | Excellent — only `createAccount` error paths uncovered |
| [Holdings.sol](src/hub/Holdings.sol) | 71/89 | **79.8%** | Good — `setAccountId` 0%, `decrease` 75% |
| [HubRegistry.sol](src/hub/HubRegistry.sol) | 30/49 | **61.2%** | `file()` and several admin setters uncovered |
| [Hub.sol](src/hub/Hub.sol) | 154/261 | **59.0%** | Many cross-chain notification functions 0% |
| [HubHelpers.sol](src/hub/HubHelpers.sol) | 46/88 | **52.3%** | `updateAccountingValue` 12.5%, `notifyDeposit/Redeem` ~45% |
| [ShareClassManager.sol](src/hub/ShareClassManager.sol) | 147/377 | **39.0%** | Lowest — claiming, queued updates, force-cancel largely uncovered |

## Function-Level Coverage: Hub.sol (59.0%)

### Fully Covered (100%)

| Function | Lines | Description |
| --- | --- | --- |
| `createPool` | 4/4 | Pool creation |
| `addShareClass` | 4/4 | Share class addition |
| `initializeHolding` | 15/15 | Holding initialization with 4 accounts |
| `updateHoldingValue` | 4/4 | Value recomputation |
| `updateHoldingAmount` | 9/9 | Amount increase/decrease |
| `updateJournal` | 5/5 | Direct journal entries |
| `depositRequest` | 3/3 | Deposit request forwarding |
| `redeemRequest` | 3/3 | Redeem request forwarding |
| `cancelRedeemRequest` | 5/5 | Cancel redeem request |
| `multicall` | 9/9 | Batch execution |
| `registerAsset` | 3/3 | Asset registration |
| `createAccount` | 3/3 | Account creation |
| `updateRestriction` | 5/5 | Restriction updates |
| `setSnapshotHook` | 3/3 | Snapshot hook setting |

### Partially Covered

| Function | Coverage | Gap |
| --- | --- | --- |
| `notifyShareClass` | 87.5% (7/8) | Error path only |
| `approveDeposits` | 85.7% (6/7) | One branch |
| `approveRedeems` | 83.3% (5/6) | One branch |
| `cancelDepositRequest` | 83.3% (5/6) | Error path |
| `issueShares` | 66.7% (4/6) | Partial |
| `revokeShares` | 66.7% (4/6) | Partial |
| `notifyDeposit` | 50.0% (3/6) | Half branches missed |
| `notifyRedeem` | 71.4% (5/7) | Some branches missed |
| `file` | 50.0% (5/10) | Config update branches |

### Completely Uncovered (0%) — 15 functions

| Function | Lines | Why Uncovered |
| --- | --- | --- |
| `notifyShareMetadata` | 5 | Cross-chain message — Gateway mocked |
| `updateShareHook` | 4 | Cross-chain message — Gateway mocked |
| `notifySharePrice` | 5 | Cross-chain notification — Gateway mocked |
| `notifyAssetPrice` | 5 | Cross-chain notification — Gateway mocked |
| `setMaxAssetPriceAge` | 4 | Cross-chain config — Gateway mocked |
| `setMaxSharePriceAge` | 4 | Cross-chain config — Gateway mocked |
| `setQueue` | 3 | Cross-chain — sends via Gateway |
| `updateShareClassMetadata` | 3 | Admin metadata update |
| `updateHubManager` | 3 | Admin config |
| `updateBalanceSheetManager` | 3 | Admin config |
| `forceCancelRedeemRequest` | 5 | No target function exposed |
| `updateSharePrice` | 3 | Not targeted (price set indirectly) |
| `initializeLiability` | 9 | No liability setup in test harness |
| `updateShares` | 4 | Share transfer — not targeted |
| `initiateTransferShares` | 4 | Cross-chain transfer — Gateway mocked |

All 0% functions fall into two categories:

1. **Cross-chain messaging** (10 functions): Gateway is mocked, so sender.send* calls are skipped
2. **Missing target functions** (5 functions): `forceCancelRedeemRequest`, `updateSharePrice`, `initializeLiability`, `updateShares`, `initiateTransferShares` have no corresponding target function in the harness

## Function-Level Coverage: ShareClassManager.sol (39.0%)

### ShareClassManager Fully Covered (100%)

| Function | Lines | Description |
| --- | --- | --- |
| `addShareClass` | 7/7 | Share class registration |
| `requestDeposit` | 3/3 | Deposit request creation |
| `cancelDepositRequest` | 6/6 | Deposit cancellation |
| `requestRedeem` | 3/3 | Redeem request creation |
| `cancelRedeemRequest` | 6/6 | Redeem cancellation |
| `nowDepositEpoch` | 2/2 | Epoch query (1-indexed) |
| `nowIssueEpoch` | 2/2 | Issue epoch query |
| `nowRedeemEpoch` | 2/2 | Redeem epoch query |
| `nowRevokeEpoch` | 2/2 | Revoke epoch query |
| `_updateMetadata` | 14/14 | Internal metadata |
| `_updatePendingDeposit` | 12/12 | Pending deposit update |
| `_updatePendingRedeem` | 6/6 | Pending redeem update |
| `_canMutatePending` | 2/2 | Mutation check |

### Critical Gaps (Partial or 0%)

| Function | Coverage | Impact |
| --- | --- | --- |
| `claimDeposit` | **14.3%** (5/35) | Core claiming logic — most branches untested |
| `claimRedeem` | **16.7%** (6/36) | Core claiming logic — most branches untested |
| `_postClaimUpdateQueued` | **0%** (0/31) | Queued cancellation after claim — never reached |
| `_updateQueued` | **17.1%** (6/35) | Queue update path — barely exercised |
| `approveDeposits` | **27.3%** (6/22) | Approval flow — many branches missed |
| `issueShares` | **16.7%** (4/24) | Share issuance — mostly uncovered |
| `revokeShares` | **29.2%** (7/24) | Share revocation — mostly uncovered |
| `approveRedeems` | **41.2%** (7/17) | Redeem approval — partial |
| `updateSharePrice` | **0%** (0/5) | Price updates — not targeted |
| `updateShares` | **9.1%** (1/11) | Share transfer — barely touched |
| `forceCancelDepositRequest` | **33.3%** (2/6) | Force cancel — partial |
| `forceCancelRedeemRequest` | **0%** (0/6) | Force cancel redeem — never called |
| `maxDepositClaims` | **0%** (0/3) | Max claims query — never called |
| `_maxClaims` | **0%** (0/4) | Internal max claims — never reached |

## Property Coverage

14 active properties in Properties.sol (80.8% line coverage overall):

| Property | Coverage | Status |
| --- | --- | --- |
| `property_total_pending_and_approved` | 100% (12/12) | Fully exercised |
| `property_sum_pending_user_deposit_geq_total_pending_deposit` | 100% (18/18) | Fully exercised |
| `property_account_totalDebit_and_totalCredit_leq_max_int128` | 100% (12/12) | Fully exercised |
| `property_accounting_and_holdings_soundness` | 100% (11/11) | Fully exercised |
| `property_asset_soundness` | 100% (16/16) | Fully exercised |
| `property_equity_soundness` | 100% (16/16) | Fully exercised |
| `property_gain_soundness` | 100% (17/17) | Fully exercised |
| `property_loss_soundness` | 100% (17/17) | Fully exercised |
| `property_user_cannot_mutate_pending_redeem` | 100% (12/12) | Fully exercised |
| `property_total_yield` | 78.9% (15/19) | Most branches exercised |
| `property_eligible_user_redemption_amount_leq_approved_asset_redemption_amount` | 70.4% (19/27) | Partial — some redeem claim paths untested |
| `property_decrease_valuation_no_increase_in_accountValue` | 57.1% (8/14) | Partial — condition rarely triggered |
| `property_epochId_can_increase_by_one_within_same_transaction` | 37.5% (6/16) | Partial — requires BATCH opType |
| `property_sum_pending_user_redeem_geq_total_pending_redeem` | 27.3% (6/22) | Low — redeem approval paths barely reached |

4 properties are commented out (WIP):

- `property_eligible_user_deposit_amount_leq_deposit_issued_amount` — stack too deep
- `property_holdings_balance_equals_escrow_balance` — may belong to vaults side
- `property_assetRegistry_balance_leq_escrow_balance` — may belong to vaults side
- `property_total_issuance_increased_after_approve_deposits_and_revoke_shares` — WIP

## Target Functions Coverage

25 shortcut/target functions in TargetFunctions.sol (87.3% line coverage):

| Function | Coverage | Notes |
| --- | --- | --- |
| `shortcut_create_pool_and_holding` | 100% | Core setup |
| `shortcut_create_pool_and_update_holding` | 100% | Setup + update |
| `shortcut_create_pool_and_update_holding_value` | 100% | Setup + value recompute |
| `shortcut_update_valuation` | 100% | Valuation update |
| `shortcut_add_share_class_and_holding` | 100% | Additional share class |
| `shortcut_approve_and_issue_shares` | 83.3% | Issue flow |
| `shortcut_approve_and_revoke_shares` | 100% | Revoke flow |
| `shortcut_deposit` | 75.0% | Basic deposit |
| `shortcut_deposit_and_claim` | 77.8% | Deposit + claim |
| `shortcut_deposit_claim_and_cancel` | 87.5% | Deposit + claim + cancel |
| `shortcut_deposit_and_cancel` | 87.5% | Deposit + cancel |
| `shortcut_request_deposit_and_cancel` | 70.0% | Request + cancel |
| `shortcut_redeem` | 100% | Basic redeem |
| `shortcut_redeem_and_claim` | 66.7% | Redeem + claim |
| `shortcut_deposit_redeem_and_claim` | 60.0% | Full deposit-redeem cycle |
| `shortcut_deposit_cancel_redemption` | 71.4% | Deposit + cancel redeem |
| `shortcut_notify_share_class` | 80.0% | Share class notification |

Shortcuts with <80% coverage indicate that internal steps fail/revert before the full sequence completes. Given that Category A (epoch assertion) fires on the first depositRequest call, most shortcuts abort early.

## Critical Coverage Gaps

### 1. Claiming Flow (claimDeposit: 14.3%, claimRedeem: 16.7%)

The most significant gap. The claim functions contain the core logic for:

- Computing payout amounts via mulDiv
- Precision loss handling (NOTE comment in L422-424)
- Pending order updates after claim
- Queued cancellation processing (`_postClaimUpdateQueued`: 0%)

This means the **rounding/precision properties have never been meaningfully tested** in the claim path.

**Root cause**: The claiming flow requires a full lifecycle: depositRequest -> approveDeposits -> issueShares -> notifyDeposit (claimDeposit internally). The Category A epoch assertion bug (see [echidna_hub_fail.md](echidna_hub_fail.md)) fires on `depositRequest`, blocking all downstream paths.

### 2. Epoch Approval Paths (approveDeposits: 27.3%, issueShares: 16.7%)

Approval and issuance require valid deposit requests to exist first. Since the epoch assertion blocks deposit requests, these functions are barely exercised.

### 3. Force Cancel Flows (forceCancelDepositRequest: 33.3%, forceCancelRedeemRequest: 0%)

`forceCancelRedeemRequest` has no target function exposed in the harness. `forceCancelDepositRequest` is only partially covered through error handling paths.

### 4. Queued Updates (_postClaimUpdateQueued: 0%, _updateQueued: 17.1%)

The queue mechanism for processing deferred cancellations during claims has zero coverage. This is a critical code path for correct deposit/redeem lifecycle handling.

### 5. Liability Accounts (initializeLiability: 0%, liabilityAccounts: 16.7%)

The test harness never creates liability holdings — only asset holdings with the standard 4-account setup (Asset, Equity, Gain, Loss). Liability accounting (Expense + Liability accounts) is completely untested.

### 6. Share Transfer (updateShares: 0%, initiateTransferShares: 0%)

No target function exists for share transfers between share classes or cross-chain share movement.

## Corpus Analysis

Only **4 coverage corpus files** — extremely small. For comparison, the E2E suite has 408. This indicates:

- Echidna found very few distinct coverage-expanding sequences
- The Category A assertion likely terminates most sequences early (the assertion fires in assertion mode, causing the fuzzer to report a failure and move on)
- The 200-step sequence length (`seqLen: 200`) is sufficient but underutilized due to early termination

## Impact of Category A on Coverage

The epoch assertion bug (`lastUpdate != depositEpochId: 1 != 0`) in `hub_depositRequest` is the **single biggest blocker** to coverage expansion:

1. Every deposit flow calls `hub_depositRequest` which fires the assertion
2. In assertion mode, Echidna treats this as a failure and records it as a reproducer
3. The fuzzer never proceeds past the depositRequest step to exercise:
   - Approval flows (`approveDeposits`, `approveRedeems`)
   - Issuance/revocation (`issueShares`, `revokeShares`)
   - Claiming (`claimDeposit`, `claimRedeem`, `_postClaimUpdateQueued`)
   - Multi-epoch lifecycle sequences

Estimated coverage after fix: Fixing Category A would likely increase `src/hub/` coverage from 54.6% to ~75-80%, with ShareClassManager.sol improving the most (from 39.0% to ~60-70%).

## Recommendations

### High Priority

1. **Fix Category A epoch assertion** — Unblocks 15 tests and enables the fuzzer to explore deposit-redeem lifecycle paths. This single fix would have the largest impact on coverage.
2. **Add `hub_forceCancelRedeemRequest` target function** — The `forceCancelRedeemRequest` flow in Hub.sol and ShareClassManager.sol is completely unreachable.
3. **Add `hub_updateSharePrice` target function** — Currently `updateSharePrice` is never called, meaning the entire share price update mechanism is untested in the hub fuzzer.

### Medium Priority

1. **Add liability holding setup** — Create a shortcut that initializes liability holdings with Expense/Liability accounts to test `initializeLiability` and the liability accounting paths.
2. **Increase multi-epoch sequences** — After fixing Category A, ensure shortcuts chain multiple approve-issue-claim cycles to exercise the multi-epoch claiming logic (`_postClaimUpdateQueued`, `_updateQueued`).
3. **Add cross-chain notification targets** — While Gateway is mocked, the 10 uncovered notification functions contain `_isManager` and parameter validation logic that could have bugs.

### Low Priority

1. **Uncomment and fix WIP properties** — Four commented-out properties could provide additional coverage if stack-too-deep and vaults-side issues are resolved.
2. **Increase corpus diversity** — Only 4 corpus files is extremely low. After fixing Category A, consider running with higher `testLimit` or different `seqLen` values.

## Summary

| Metric | Value |
| --- | --- |
| Target module (src/hub/) coverage | **54.6%** |
| Accounting.sol | **90.8%** (excellent) |
| Holdings.sol | **79.8%** (good) |
| Hub.sol | **59.0%** (moderate — cross-chain gaps) |
| ShareClassManager.sol | **39.0%** (critical gaps in claiming) |
| Active properties exercised | 10/14 fully, 4/14 partial |
| Properties with >70% coverage | 10/14 |
| Corpus sequences | 4 (very low) |
| Biggest blocker | Category A epoch assertion bug |
