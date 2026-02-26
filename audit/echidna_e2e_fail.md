# Echidna E2E Fuzzing Fail Analysis

## Overview

8 Echidna E2E reproducers found across 4 property violations. All reproducers have been replayed in Foundry.

| Category | Property | Fails | properties-table | Status |
|---|---|---|---|---|
| A | `property_holdings_balance_equals_escrow_balance` | 2 | #49 ✅ | **Property Bug (Inverted Precondition)** |
| B | `property_totalAssets_solvency` | 2 | #26 ❌ | Known (admin NAV) |
| C | `property_sum_of_minted_equals_total_supply` | 2 | #16 ❌ | Known (ghost tracking) |
| D | `property_escrow_balance` | 2 | #23 ❌ | Known (ghost tracking) |

---

## Category A: `property_holdings_balance_equals_escrow_balance` (Deep Dive)

### Reproducers

| ID | Vault Type | Sequence |
|---|---|---|
| #7835402543848108176 | SyncDepositVault | `deployNewTokenPoolAndShare(0, big, false, false, false)` -> `deposit_sync(assets=1, navPerShare=60442435263903437)` -> check |
| #984593248541434999 | SyncDepositVault | `deployNewTokenPoolAndShare(0, big, false, false, false)` -> `deposit_sync(assets=1, navPerShare=7364027)` -> check |

### Foundry Reproduction

```
[FAIL: holding != escrow balance: 0 != 1] test_property_holdings_balance_equals_escrow_balance_echidna_1()
[FAIL: holding != escrow balance: 0 != 1] test_property_holdings_balance_equals_escrow_balance_echidna_2()
```

### Root Cause: Inverted Precondition in Property

**The property's precondition check is inverted.** The comment and code contradict each other:

```solidity
// Properties.sol:886-889
// precondition: if queue is enabled, holdings don't get updated until the queue is submitted
if(!balanceSheet.queueDisabled(vault.poolId(), vault.scId())) {
    eq(holdingAssetAmount, escrowBalance, "holding != escrow balance");
}
```

- **Comment says**: "if queue is enabled, holdings don't get updated" (= don't check when queue is enabled)
- **Code does**: `if(!queueDisabled)` = if queue IS enabled, DO check
- **Should be**: `if(balanceSheet.queueDisabled(...))` (without the `!`)

### Detailed Call Flow

```
shortcut_deposit_sync(assets=1, navPerShare=7364027)
  |
  +--> hub_updateSharePrice()            # Sets D18 price on Hub
  +--> hub_notifyAssetPrice()            # Price notification only (no Holdings update)
  +--> hub_notifySharePrice()            # Price notification only (no Holdings update)
  |
  +--> vault.deposit(1, actor)           # SyncDepositVault.deposit
         |
         +--> SyncRequestManager.deposit()
         |      |
         |      +--> previewDeposit(1)   # Calculates shares (non-zero due to low price)
         |      +--> _issueShares(shares, 1 wei)
         |             |
         |             +--> balanceSheet.issue()         # Shares: queued (queue enabled)
         |             |      +--> token.mint(actor, shares)  # Shares minted regardless!
         |             |
         |             +--> balanceSheet.noteDeposit(1 wei)
         |                    +--> escrow.deposit()          # Escrow accounting updated
         |                    +--> _updateAssets(1 wei)
         |                           |
         |                           +--> queueDisabled? NO (default)
         |                           +--> assetQueue.deposits += 1   # QUEUED ONLY
         |                           +--> Holdings NOT updated!      # <-- ROOT CAUSE
         |
         +--> SafeTransferLib.safeTransferFrom(1 wei -> Escrow)  # Token actually transferred
```

### Debug Output

```
=== BEFORE deposit_sync ===
holdingAssetAmount: 0
escrowBalance: 0
queueDisabled: false              <-- Queue IS enabled (default)

=== deposit_sync(assets=1, navPerShare=7364027) ===
shares minted: 184403540726833293794278592406030015913    <-- ~1.84e38 shares for 1 wei!

=== AFTER deposit_sync ===
holdingAssetAmount: 0             <-- NOT updated (queued)
escrowBalance: 1                  <-- Updated (token transferred)
delta holding: 0
delta escrow: 1
```

### Comparison with Existing Reproducer

| | Existing (test_0) | Echidna #1 | Echidna #2 |
|---|---|---|---|
| Vault | AsyncVault+SyncDeposit | SyncDepositVault | SyncDepositVault |
| Deploy params | `(0,1,true,false,true)` | `(0,big,false,false,false)` | `(0,big,false,false,false)` |
| Deposit flow | `deposit_and_claim` | `deposit_sync` | `deposit_sync` |
| Existing NOTE | "price=0 causes holdingAssetAmount=0" | N/A | N/A |
| **Actual root cause** | **Inverted precondition** | **Inverted precondition** | **Inverted precondition** |

The existing reproducer's NOTE about "price=0" is a **misdiagnosis**. The actual root cause in ALL cases is the inverted precondition: Holdings is never updated when queue is enabled (default), but the property checks in exactly that state.

### Assessment

**Severity: Property Bug (not a protocol vulnerability)**

The `holdingAssetAmount != escrowBalance` discrepancy is EXPECTED behavior when the balance sheet queue is enabled — deposits are batched and Holdings is only updated when the queue is submitted. The property's precondition incorrectly checks this invariant during the batching phase.

**Fix**: Change line 887 from `if(!balanceSheet.queueDisabled(...))` to `if(balanceSheet.queueDisabled(...))` to match the comment's intent.

**properties-table.md #49**: Should be annotated as "property bug — inverted precondition" rather than ✅.

### Secondary Finding: Dust Deposit DoS via Unbounded navPerShare

#### Summary

`updateSharePrice()` has no minimum price validation. When admin sets extremely low `navPerShare`, a 1 wei dust deposit can mint enough shares to hit `ShareToken.mint()`'s `ExceedsMaxSupply` guard, permanently blocking all future deposits for that share class.

#### Foundry Verification

```
=== navPerShare=7364027 (D18: ~7.36e-12) ===
1st deposit (1 wei): totalSupply = 1.84e38 (54% of uint128.max)
2nd deposit (1 wei): REVERTED - ExceedsMaxSupply
-> DoS after 2 dust deposits

=== navPerShare=1 (D18: 1e-18, minimum non-zero) ===
1st deposit (1 wei): REVERTED - ExceedsMaxSupply
-> DoS on FIRST dust deposit
```

#### DoS Threshold

- Single 1 wei deposit DoS: `navPerShare < ~4,000,000` (D18: ~4e-12)
- Double 1 wei deposit DoS: `navPerShare < ~7,400,000` (D18: ~7.4e-12)
- Team's test MIN_PRICE: `1e14` (D18: 0.0001) — 25 million x above threshold, safe if enforced
- Protocol enforcement: **NONE** — `updateSharePrice()` accepts any D18 value

#### Root Cause

```solidity
// ShareClassManager.sol:327-333
function updateSharePrice(PoolId poolId, ShareClassId scId_, D18 navPoolPerShare) external auth {
    require(exists(poolId, scId_), ShareClassNotFound());
    m.navPerShare = navPoolPerShare;  // No min/max validation
}
```

The protection exists in `ShareToken.mint()` (L100: `require(totalSupply <= type(uint128).max)`), which prevents overflow but converts the issue into a DoS: once totalSupply nears `type(uint128).max`, no further mints are possible.

#### Attack Scenario (Theoretical)

1. Admin (or compromised admin) sets `navPerShare = 1` via `updateSharePrice()`
2. Attacker deposits 1 wei of the asset token
3. `SyncRequestManager.deposit()` calculates shares ≈ `pricePoolPerAsset / 1` ≈ 1.355e45
4. `ShareToken.mint()` reverts with `ExceedsMaxSupply`
5. All deposits for this share class are blocked until admin recovers

#### Realistic Attack Assessment

| Question | Answer |
|---|---|
| Can external attacker execute? | **NO** — `updateSharePrice()` requires `_isManager(poolId)` (Pool Manager only) |
| Can admin accidentally trigger? | **Extremely unlikely** — navPerShare < 4e6 (D18: ~4e-12) is an absurdly small price |
| Initial state (price=0) safe? | **YES** — `PricingLib.assetToShareAmount()` returns 0 when `pricePoolPerShare == 0` |
| Recoverable? | **YES** — admin can `burn()` inflated shares (auth modifier) and reset price |
| If admin is compromised? | DoS is the **least** concern — compromised admin can directly drain funds |
| Fixed in release-v3.0.0? | **NO** — same code, no min price validation |
| Fixed in main (latest)? | **NO** — `computedAt` timestamp added but still no min price validation |

#### Cross-Branch Comparison

```solidity
// audited (v3.1) & release-v3.0.0: identical
function updateSharePrice(..., D18 navPoolPerShare) external auth {
    require(exists(poolId, scId_), ShareClassNotFound());
    m.navPerShare = navPoolPerShare;  // No min/max
}

// main (latest): timestamp added, still no min/max
function updateSharePrice(..., D18 pricePoolPerShare_, uint64 computedAt) external auth {
    require(exists(poolId, scId_), ShareClassNotFound());
    require(computedAt <= block.timestamp, CannotSetFuturePrice());  // NEW
    p.price = pricePoolPerShare_;  // Still no min/max
}
```

#### Severity Assessment

**Severity: Informational**

This is within the admin trust model. The attack requires Pool Manager access, and a compromised admin has far more damaging options available. The DoS is recoverable via `burn()`. As a defensive programming measure, adding `require(navPoolPerShare >= MIN_PRICE)` is recommended (the team already uses `MIN_PRICE = 1e14` in PricingLib tests but does not enforce it in contracts).

---

## Category B: `property_totalAssets_solvency` (Known)

### Reproducers

| ID | Sequence |
|---|---|
| #518862186988112175 | deploy(AsyncVault) -> deployVault -> `updateSharePrice(222132857126451087)` -> deposit_and_cancel -> `balanceSheet_issue(573...)` -> check |
| #1127038780738260532 | deploy(AsyncVault) -> deployVault -> `updateSharePrice(441805741455)` -> deposit_and_cancel -> `balanceSheet_issue(573...)` -> check |

### Foundry Reproduction (Category B)

```text
[FAIL: totalAssets > actualAssets: 1 > 0] test_echidna_totalAssets_solvency_1()
[FAIL: totalAssets > actualAssets: 1 > 0] test_echidna_totalAssets_solvency_2()
```

Both reproducers confirmed. `totalAssets` reports 1 while actual escrow balance is 0 — the vault claims to hold more assets than it actually does.

**properties-table.md #26**: ❌ (known fail)

**Root cause**: Admin can set arbitrary NAV via `updateSharePrice`, which changes the share price and breaks totalAssets solvency when combined with `balanceSheet_issue`. The `totalAssets()` calculation uses the admin-set price to compute asset value, creating a phantom 1 wei discrepancy.

**Assessment**: Known admin trust assumption issue. Not a vulnerability unless admin is untrusted.

---

## Category C: `property_sum_of_minted_equals_total_supply` (Known)

### Reproducers

| ID | Vault Type | Sequence |
|---|---|---|
| #4993392222817840976 | AsyncVault | deploy -> `updateSharePrice(2177124214410)` -> request_deposit -> asyncVault_maxDeposit -> check |
| #7795426837052371256 | SyncDepositVault | deploy -> `updateSharePrice(2407785)` -> request_deposit -> asyncVault_maxDeposit -> check |

### Foundry Reproduction (Category C)

```text
[FAIL: totalSupply != ghostTotalSupply: 10000000000000000000000000000000000 != 0] test_echidna_sum_minted_total_supply_1()
[FAIL: totalSupply != ghostTotalSupply: 84407000000000000000000000000000000000 != 0] test_echidna_sum_minted_total_supply_2()
```

Both reproducers confirmed. `ghostTotalSupply` remains 0 while actual `totalSupply` is non-zero (1e34 and 8.4e37 respectively) — the ghost tracker never recorded the mint events.

**properties-table.md #16**: ❌ (known fail)

**Root cause**: Ghost variable `ghostMinted` tracking doesn't properly account for sync deposit flows and maxDeposit operations. The `asyncVault_maxDeposit` target function triggers internal mint paths that bypass ghost variable updates. This is a test harness tracking issue, not a protocol bug.

---

## Category D: `property_escrow_balance` (Known)

### Reproducers

| ID | Vault Type | Sequence |
|---|---|---|
| #6931770679071936629 | AsyncVault | deploy -> `updateSharePrice(17582)` -> request_deposit -> asyncVault_maxDeposit -> check |
| #4928776995980949899 | SyncDepositVault | deploy -> `updateSharePrice(0)` -> request_deposit -> asyncVault_maxDeposit -> check |

### Foundry Reproduction (Category D)

```text
[FAIL: balOfEscrow != ghostBalOfEscrow: 1 != 0] test_echidna_escrow_balance_1()
[FAIL: balOfEscrow != ghostBalOfEscrow: 1 != 0] test_echidna_escrow_balance_2()
```

Both reproducers confirmed. Actual escrow balance is 1 while ghost tracker reports 0 — the ghost variable never recorded the escrow deposit.

**properties-table.md #23**: ❌ (known fail)

**Root cause**: Same ghost variable tracking issue as Category C. The `asyncVault_maxDeposit` target function's internal operations cause escrow balance ghost variables to become stale. The `request_deposit` flow transfers 1 wei to escrow, but the ghost tracking in `afterCall` doesn't capture this update path.

---

## Summary

| Finding | Type | Severity | Action Required |
|---|---|---|---|
| Category A: Inverted precondition | Property bug | Informational | Fix `!` in condition (line 887 of Properties.sol) |
| Category A: Excessive share minting | Protocol concern | Informational | Consider min price validation in `updateSharePrice` |
| Category B: Admin NAV breaks solvency | Known | N/A | Already tracked |
| Category C: Ghost tracking mismatch | Test harness | N/A | Already tracked |
| Category D: Ghost tracking mismatch | Test harness | N/A | Already tracked |
