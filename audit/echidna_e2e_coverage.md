# Echidna E2E Coverage Analysis

## Overview

- **Fuzzer**: Echidna (assertion mode, 100M test limit, seqLen=300, 16 workers)
- **Contract**: `CryticE2ETester`
- **Corpus**: `echidna_e2e/` (408 coverage files, 8 reproducers)
- **Coverage Report**: `covered.1771862713` (latest run)
- **Overall Protocol Coverage**: **50.7%** (2,429 / 4,789 instrumented lines)

---

## Per-File Coverage (Protocol src/ only)

### Tier 1: Excellent (85%+)

| File | Coverage | Lines | Notes |
|------|----------|-------|-------|
| Accounting.sol | **100.0%** | 65/65 | Fully covered - journal, debit/credit, accounts |
| FullRestrictions.sol | **98.3%** | 57/58 | Freeze + memberlist hook |
| PricingLib.sol | **96.7%** | 87/90 | Share/asset conversions, price math |
| AssetManager.sol | **96.6%** | 28/29 | Asset registration |
| AsyncRequestManager.sol | **96.1%** | 224/233 | Deposit/redeem request lifecycle |
| ShareClassManager.sol | **95.0%** | 358/377 | Epochs, approvals, issuance |
| ShareToken.sol | **93.4%** | 57/61 | ERC20+hooks, mint/burn/transfer |
| AsyncVault.sol | **92.3%** | 48/52 | Async deposit/redeem |
| Auth.sol | **91.7%** | 11/12 | rely/deny/auth modifier |
| Hub.sol | **90.4%** | 236/261 | Core hub orchestration |
| Holdings.sol | **88.8%** | 79/89 | Asset holding tracking |
| Escrow.sol | **88.4%** | 38/43 | Token custody |
| AsyncVaultFactory.sol | **88.2%** | 15/17 | Vault deployment |
| SyncDepositVaultFactory.sol | **86.4%** | 19/22 | Sync vault deployment |
| SyncRequestManager.sol | **85.3%** | 99/116 | Sync deposit logic |
| BaseRequestManager.sol | **84.7%** | 50/59 | Shared request manager base |
| PoolEscrowFactory.sol | **84.4%** | 27/32 | Escrow creation |
| HubHelpers.sol | **84.1%** | 74/88 | notifyDeposit/Redeem, accounting helpers |

### Tier 2: Good (65-85%)

| File | Coverage | Lines | Gaps |
|------|----------|-------|------|
| Spoke.sol | **80.2%** | 195/243 | `transferShares()`, `updateShareHook()`, `updateVault()` |
| HubRegistry.sol | **73.5%** | 36/49 | Some manager/configuration functions |
| BalanceSheet.sol | **65.5%** | 108/165 | `submitQueuedAssets()`, `submitQueuedShares()` fully uncovered |

### Tier 3: Moderate (50-65%)

| File | Coverage | Lines | Gaps |
|------|----------|-------|------|
| TokenFactory.sol | **63.0%** | 17/27 | Share token creation edge cases |
| SyncDepositVault.sol | **62.5%** | 10/16 | `file()` configuration |
| BaseVaults.sol | **61.9%** | 91/147 | `authorizeOperator()` (ERC7741), `setOperator()`, DOMAIN_SEPARATOR |
| D18.sol | **60.0%** | 18/30 | Fixed-point arithmetic edge cases |
| SafeTransferLib.sol | **59.1%** | 13/22 | Some transfer paths |
| MathLib.sol | **51.5%** | 35/68 | mulDiv rounding variants |
| BaseValuation.sol | **50.0%** | 4/8 | Some valuation paths |

### Tier 4: Critical Gaps (0%)

| File | Lines | Reason |
|------|-------|--------|
| **VaultRouter.sol** | 108 | Not in E2E scope (UX wrapper) |
| **Gateway.sol** | 148 | Mocked - cross-chain router |
| **MessageDispatcher.sol** | 250 | Mocked - message serialization |
| **MessageProcessor.sol** | 169 | Mocked - message deserialization |
| **MultiAdapter.sol** | 108 | Not mocked but requires adapter coordination |
| **LegacyVaultAdapter.sol** | 80 | Legacy migration, out of scope |
| **FreezeOnly.sol** | 42 | Alternative hook (FullRestrictions used instead) |
| **RedemptionRestrictions.sol** | 59 | Alternative hook (FullRestrictions used instead) |
| **Guardian.sol** | 44 | Emergency pause, not in E2E path |
| **GasService.sol** | 8 | Cross-chain gas, mocked out |
| **TokenRecoverer.sol** | 11 | Recovery utility, not in main path |
| **Adapters** (Axelar/Wormhole) | 71 | External bridge adapters, mocked |
| **MessageLib.sol** | 392 (0.3%) | Serialization library, bypassed by mocks |

---

## Coverage by Module

| Module | Coverage | Hit/Total | Key Observations |
|--------|----------|-----------|-----------------|
| **hub/** | **89.7%** | 848/945 | Best covered module. Core protocol logic well-tested |
| **spoke/** | **76.3%** | 453/594 | Good but queue submission uncovered |
| **vaults/** | **65.4%** | 556/850 | VaultRouter 0%, BaseVaults operator auth uncovered |
| **hooks/** | **62.7%** | 74/118 | FullRestrictions excellent, alternatives unused |
| **common/** | **7.8%** | 129/1,647 | Cross-chain infrastructure entirely mocked |
| **misc/** | **44.3%** | 194/438 | Libraries partially covered |

---

## Critical Uncovered Functions (Security-Relevant)

### BalanceSheet.sol - Queue Submission (0% covered)

```
submitQueuedAssets()  - Lines 183-210 - FULLY UNCOVERED
submitQueuedShares()  - Lines 214-230 - FULLY UNCOVERED
```

**Impact**: These are the functions that flush the balance sheet queue to Holdings. When `queueDisabled == false` (default), deposits/redeems accumulate in the queue and are submitted in batch. This entire batch submission path is never exercised.

**Risk**: HIGH - Queue→Holdings transition is a critical state change that could have rounding/ordering bugs.

### BaseVaults.sol - Operator Authorization (0% covered)

```
authorizeOperator()  - Lines 117-139 - FULLY UNCOVERED
setOperator()        - Lines 94-98  - PARTIALLY UNCOVERED
setEndorsedOperator() - Lines 103-105 - PARTIALLY UNCOVERED
```

**Impact**: ERC-7741 permit-style operator authorization via EIP-712 signatures. No coverage of signature validation, nonce management, or deadline checks.

**Risk**: MEDIUM - Signature validation bugs could allow unauthorized vault operations.

### Spoke.sol - Cross-chain Operations (0% covered)

```
transferShares()   - Lines 98-115  - FULLY UNCOVERED
updateShareHook()  - Lines 220-223 - FULLY UNCOVERED
updateVault()      - Lines 307-322 - FULLY UNCOVERED
```

**Impact**: Cross-chain share transfers, hook updates, and vault configuration. All bypassed by mock gateway.

**Risk**: MEDIUM - These functions are gated by auth modifier but contain complex state transitions.

### Hub.sol - Partial Gaps

```
updateHubManager()         - Lines 272-275 - PARTIALLY UNCOVERED
updateBalanceSheetManager() - Line 286     - PARTIALLY UNCOVERED
updateRestriction()        - Lines 429-433 - PARTIALLY UNCOVERED
updateContract()           - Line 447      - PARTIALLY UNCOVERED
```

**Impact**: Admin configuration functions for updating managers and restrictions across chains.

**Risk**: LOW - Auth-gated, but configuration bugs could break cross-chain consistency.

### SyncRequestManager.sol - Valuation Update (0% covered)

```
update()  - Lines 66-85 - FULLY UNCOVERED
```

**Impact**: Updates valuation source and max reserve for sync vaults. Changes how deposits are priced.

**Risk**: MEDIUM - Valuation changes affect all subsequent deposit/mint calculations.

---

## Target Function → Protocol Function Mapping

### Well-Explored Paths (Full Lifecycle Tested)

| Flow | Target Functions | Coverage |
|------|-----------------|----------|
| **Async Deposit** | `requestDeposit` → `approveDeposits` → `issueShares` → `notifyDeposit` → `claimDeposit` | ✅ Full |
| **Async Redeem** | `requestRedeem` → `approveRedeems` → `revokeShares` → `notifyRedeem` → `claimRedeem` | ✅ Full |
| **Sync Deposit** | `shortcut_deposit_sync` → `vault.deposit/mint` | ✅ Full |
| **Cancel Deposit** | `cancelDepositRequest` → `claimCancelDepositRequest` | ✅ Full |
| **Cancel Redeem** | `cancelRedeemRequest` → `claimCancelRedeemRequest` | ✅ Full |
| **Share Pricing** | `updateSharePrice` → `previewDeposit/Redeem` | ✅ Full |
| **Pool Setup** | `createPool` → `addShareClass` → `deployVault` → `linkVault` | ✅ Full |
| **Member Mgmt** | `updateMember` → `freeze/unfreeze` → `transfer` | ✅ Full |
| **Accounting** | `createAccount` → `updateJournal` → `accountValue` | ✅ Full |
| **Holdings** | `initializeHolding` → `updateHoldingValue` → `amount/value` | ✅ Full |
| **Doomsday** | `deposit/mint/redeem/withdraw` with rounding checks | ✅ Full |

### Partially Explored Paths

| Flow | What's Covered | What's Missing |
|------|---------------|----------------|
| **Queue Mechanism** | Queue accumulation (`noteDeposit` with `queueDisabled=false`) | `submitQueuedAssets()`, `submitQueuedShares()` never called |
| **Force Cancel** | `forceCancelDepositRequest` target exists | `forceCancelRedeemRequest` partially covered |
| **Liability Holdings** | `initializeLiability` target exists | Liability decrease path in Holdings |
| **Multi-vault per Pool** | Single vault deployed per pool in most sequences | Multi-vault interactions not explored |
| **ERC6909 Assets** | Standard ERC20 deposits | ERC6909 token deposit path in BalanceSheet.deposit() |

### Unexplored Paths (No Target Functions)

| Path | Description | Risk |
|------|-------------|------|
| **VaultRouter multicall** | Batched user operations via router | MEDIUM - ordering/reentrancy |
| **authorizeOperator (ERC-7741)** | Signature-based operator auth | MEDIUM - signature validation |
| **Queue submission** | `submitQueuedAssets/Shares` batch flush | HIGH - state transition |
| **Cross-chain share transfer** | `Spoke.transferShares()` | MEDIUM - auth-gated |
| **Hook updates** | `updateShareHook()` on Spoke | LOW - admin operation |
| **Legacy vault migration** | `LegacyVaultAdapter` bridge | LOW - optional feature |
| **Recovery flows** | `MultiAdapter.initiateRecovery/disputeRecovery` | HIGH - emergency mechanism |
| **Snapshot hooks** | `Holdings.setSnapshotHook()` | LOW - optional feature |

---

## Properties Assessment

### Properties Table Summary

| Status | Count | % |
|--------|-------|---|
| ✅ Passing | 60 | 83.3% |
| ❌ Failing | 12 | 16.7% |
| **Total** | **72** | **100%** |

### Failing Properties Breakdown

| # | Property | Root Cause | Real Bug? |
|---|----------|-----------|-----------|
| 3 | maxDeposit decrease | Ghost tracking mismatch | No - harness issue |
| 11 | maxRedeem decrease | Ghost tracking mismatch | No - harness issue |
| 13 | sum_of_shares_received | Ghost tracking mismatch | No - harness issue |
| 15 | sum_of_pending_redeem | Ghost tracking mismatch | No - harness issue |
| 16 | sum_of_minted_equals_total_supply | Ghost tracking bypass via maxDeposit | No - harness issue |
| 19 | sum_of_received_leq_fulfilled | Ghost tracking mismatch | No - harness issue |
| 23 | escrow_balance | Ghost tracking bypass via maxDeposit | No - harness issue |
| 24 | escrow_share_balance | Ghost tracking mismatch | No - harness issue |
| 26 | totalAssets_solvency | Admin NAV + balanceSheet_issue | Known - admin trust |
| 45 | equity_soundness | Admin NAV manipulation | Known - admin trust |
| 47 | loss_soundness | Admin NAV manipulation | Known - admin trust |
| 50 | total_issuance_soundness | Admin NAV manipulation | Known - admin trust |
| 60 | hub_notifyDeposit lastUpdate | Epoch tracking edge case | Investigate |

**Verdict**: 8 are ghost variable tracking issues (harness bugs), 4 are known admin trust assumptions, 1 needs investigation (#60).

---

## Assessment: Is the Fuzzing Campaign Exhaustive?

### Strengths

1. **Core deposit/redeem lifecycle thoroughly tested** - All major user flows (request → approve → issue/revoke → notify → claim) are fully covered with 130+ target functions
2. **Hub module at 89.7%** - The most critical component has excellent coverage
3. **72 properties** covering solvency, accounting, epoch consistency, pricing, and edge cases
4. **Shortcut functions** enable deeper state exploration (e.g., `shortcut_deposit_and_claim` reaches states requiring 5+ sequential calls)
5. **Doomsday targets** specifically test rounding and precision edge cases
6. **seqLen=300** allows extremely deep state exploration sequences

### Weaknesses

1. **Queue submission path completely untested** - `submitQueuedAssets()` and `submitQueuedShares()` are never called despite being the critical batch flush mechanism
2. **Cross-chain infrastructure entirely mocked** - Gateway, MessageDispatcher, MessageProcessor, MultiAdapter all at 0%. This is expected for local fuzzing but means no E2E coverage of message serialization/routing
3. **VaultRouter at 0%** - The primary EOA entry point is never tested in E2E, including its multicall batching
4. **ERC-7741 operator authorization untested** - Signature validation in `authorizeOperator()` never exercised
5. **8 ghost variable failures mask potential issues** - When ghost tracking is broken, the fuzzer can't detect real accounting bugs via those properties
6. **Single vault per pool** - Multi-vault interactions within the same pool are underexplored
7. **ERC6909 asset deposits untested** - Only standard ERC20 deposits exercised

### Verdict

The E2E fuzzing campaign provides **strong coverage of the core protocol logic** (hub operations, vault lifecycle, share pricing, accounting). The 89.7% hub coverage and 85%+ coverage on critical managers/request handlers demonstrates thorough exploration of the main user paths.

However, there are **meaningful gaps**:

| Gap | Severity | Recommendation |
|-----|----------|---------------|
| Queue submission (`submitQueuedAssets/Shares`) | **HIGH** | Add target function for batch queue flush |
| Ghost variable tracking (8 broken properties) | **HIGH** | Fix ghost tracking to restore property power |
| VaultRouter multicall | **MEDIUM** | Add VaultRouter target functions |
| `authorizeOperator` (ERC-7741) | **MEDIUM** | Add signature-based auth target |
| ERC6909 deposits | **MEDIUM** | Add ERC6909 token variant in setup |
| Multi-vault per pool | **LOW** | Deploy multiple vaults in shortcut |
| Cross-chain mocks | **Expected** | Covered by separate unit tests |

**Overall**: The campaign has explored the most critical paths well, but the queue submission gap and broken ghost variables are significant. The queue submission functions are the bridge between the spoke's local accounting and the hub's global state - testing them would significantly strengthen the invariant suite.
