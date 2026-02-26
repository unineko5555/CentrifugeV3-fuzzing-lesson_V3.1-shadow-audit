# Echidna Hub Fuzzing Fail Analysis

## Overview

26 CryticToFoundry tests: **6 passed, 20 failed**. 11 new Echidna reproducers found in `echidna_hub/reproducers/`, plus 3 existing reproducers from a prior run (2026-02-20). All failures categorized into 5 root causes.

| Category | Error Message | Fails | Root Cause | Severity |
| --- | --- | --- | --- | --- |
| A | `lastUpdate != depositEpochId: 1 != 0` | 15 | Property bug (1-indexed vs 0-indexed epoch) | Property Bug |
| B | `totalDebit is greater than max int128` | 1 | Missing input validation in `updateHoldingAmount` | Low |
| C | `accountValue increased` | 1 | Property too broad (checks all 6 account types) | Property Bug |
| D | `lastUpdate is > latest redeem approval: 0 <= 0` | 1 | Property fires in initial state (0 == 0) | Property Bug |
| E | `Price not set` | 1 | Test setup missing price initialization | Test Harness |

### Echidna Reproducers to Category Mapping

All 11 new Echidna reproducers (from `echidna_hub/reproducers/`) map to **Category A**:

| Reproducer ID | Call Sequence | Category |
| --- | --- | --- |
| #1300196428570193753 | `shortcut_deposit_and_claim(6,1,1,false,0,0,0)` | A |
| #3615079815534453981 | `shortcut_deposit_redeem_and_claim(6,1,1,false,0,0,0)` | A |
| #3819119124072349209 | `shortcut_update_valuation(6,1,1,false)` then `hub_cancelDepositRequest_clamped(0,0)` | A |
| #4426448990206989301 | `shortcut_request_deposit_and_cancel(6,1,1,false,0,0,0)` | A |
| #5674401236964196037 | `shortcut_deposit(6,1,1,false,0,0,0)` | A |
| #6304454715097308992 | `shortcut_deposit_cancel_redemption(6,1,1,false,0,0,0)` | A |
| #7751327755016350357 | `shortcut_create_pool_and_holding(6,1,big,false)` then `hub_cancelRedeemRequest_clamped(0,0)` | A |
| #7798316022853808170 | `shortcut_notify_share_class(6,1,365592437991562,false,0,0,0)` | A |
| #8054514036650090164 | `shortcut_create_pool_and_holding(6,1,big,false)` then `hub_depositRequest_clamped(0,0,0)` | A |
| #8474275748834685106 | `shortcut_deposit_and_cancel(6,1,1,false,0,0,0)` | A |
| #9214097362533186247 | `shortcut_deposit_claim_and_cancel(6,1,1,false,0,0,0)` | A |

9 of 11 use `amount=0, maxApproval=0, navPerShare=0` — the epoch tracking assertion fires on the very first `depositRequest` call, before any meaningful deposit operations occur.

3 existing reproducers (2026-02-20 run, already in CryticToFoundry.sol):

| Test | Category |
| --- | --- |
| `test_echidna_totalDebit_exceeds_int128_max` | B |
| `test_echidna_decrease_valuation_increases_accountValue` | C |
| `test_echidna_user_mutates_pending_redeem` | D |

---

## Category A: `lastUpdate != depositEpochId: 1 != 0` (15/20 failures)

### Category A Root Cause: 1-Indexed vs 0-Indexed Epoch Comparison

The inline property in `AdminTargets.sol` compares two values using different epoch indexing:

```solidity
// AdminTargets.sol:226-232
(uint128 pending, uint32 lastUpdate) = shareClassManager.depositRequest(scId, depositAssetId, investor);
(uint32 depositEpochId,,, ) = shareClassManager.epochId(scId, depositAssetId);

if(Helpers.canMutate(lastUpdate, pending, depositEpochId)) {
    eq(lastUpdate, depositEpochId, "lastUpdate != depositEpochId");  // <-- BUG
}
```

The protocol sets `lastUpdate` to `nowDepositEpoch()`:

```solidity
// ShareClassManager.sol:452-454
userOrder.lastUpdate = nowDepositEpoch(scId_, depositAssetId);  // = epochId.deposit + 1

function nowDepositEpoch(ShareClassId scId_, AssetId depositAssetId) public view returns (uint32) {
    return epochId[scId_][depositAssetId].deposit + 1;  // 1-indexed (current open epoch)
}
```

But the property reads `depositEpochId` from `epochId()` which is 0-indexed:

```solidity
(uint32 depositEpochId,,, ) = shareClassManager.epochId(scId, depositAssetId);
// Returns the raw epochId.deposit = 0 (last completed approval epoch)
```

Result: `lastUpdate = 1` (from `nowDepositEpoch`) vs `depositEpochId = 0` (from `epochId`). The assertion `eq(1, 0)` always fails after the first deposit request.

The `canMutate` precondition passes because:

```solidity
// Helpers.sol:61-62
function canMutate(uint32 lastUpdate, uint128 pending, uint128 latestApproval) internal pure returns (bool) {
    return lastUpdate > latestApproval || pending == 0 || latestApproval == 0;
    // 1 > 0 -> true
}
```

### Same Bug in cancelDepositRequest and cancelRedeemRequest

The identical pattern appears in:

- `hub_cancelDepositRequest` (AdminTargets.sol:289-291): `eq(lastUpdateAfter, depositEpochId, "lastUpdate != depositEpochId")`
- `hub_cancelRedeemRequest` (AdminTargets.sol:331-332): `eq(lastUpdateAfter, redeemEpochId, "lastUpdate != redeemEpochId")`

### Category A Affected Tests (15)

All tests that call any deposit/cancel flow trigger this:

```text
test_calling_claimDeposit_directly, test_cancel_redeem_request, test_deposit_and_cancel,
test_hub_depositRequest_clamped_4, test_notify_share_class, test_property_accounting_and_holdings_soundness_0,
test_property_user_cannot_mutate_pending_redeem_2, test_request_deposit, test_request_redeem,
test_shortcut_deposit_and_claim, test_shortcut_deposit_cancel_redemption,
test_shortcut_deposit_claim_and_cancel, test_shortcut_deposit_redeem_and_claim,
test_shortcut_notify_share_class, test_shortcut_redeem_and_claim,
test_shortcut_request_deposit_and_cancel
```

### Category A Fix

Change the epoch comparison to use the same 1-indexed value:

```solidity
// Option 1: Use nowDepositEpoch() directly
uint32 currentEpoch = shareClassManager.nowDepositEpoch(scId, depositAssetId);
eq(lastUpdate, currentEpoch, "lastUpdate != currentEpoch");

// Option 2: Add 1 to the 0-indexed value
eq(lastUpdate, depositEpochId + 1, "lastUpdate != depositEpochId + 1");
```

Apply the same fix to `hub_cancelDepositRequest` and `hub_cancelRedeemRequest` (using `nowRedeemEpoch` for the redeem side).

### Category A Assessment

Severity: Property Bug (not a protocol vulnerability)

The underlying protocol behavior is correct — `lastUpdate` is set to `nowDepositEpoch()` by design. The off-by-one is entirely in the test harness assertion. This bug masks all 15 tests, preventing other properties from being meaningfully exercised in those flows.

---

## Category B: `totalDebit is greater than max int128` (1/20 failures)

### Category B Reproducer

```solidity
// CryticToFoundry.sol:279-284
function test_echidna_totalDebit_exceeds_int128_max() public {
    shortcut_create_pool_and_update_holding(6, 1, 2, true, 1);
    hub_updateHoldingAmount_clamped(0, 0, 0, 170315956445675341242596003749085484523, 0);
    hub_addShareClass_clamped(0, 1);
    hub_updateHoldingValue_clamped(0, 0);
    property_account_totalDebit_and_totalCredit_leq_max_int128();
}
```

### Category B Foundry Reproduction

```text
[FAIL: totalDebit is greater than max int128: 170315956445675341242596003749085484523 > 170141183460469231731687303715884105727]
test_echidna_totalDebit_exceeds_int128_max()
```

### Category B Root Cause: No int128 Bounds Check on updateHoldingAmount

`hub_updateHoldingAmount` (AdminTargets.sol:357-381) accepts any `uint128 amount` and passes it directly to the Hub:

```solidity
hub.updateHoldingAmount(
    CENTIFUGE_CHAIN_ID, poolId, scId, assetId,
    amount,        // <-- No validation that amount <= type(int128).max
    D18.wrap(pricePoolPerAsset), isIncrease, isSnapshot, nonce
);
```

Inside Accounting.sol, `addDebit` simply accumulates:

```solidity
acc.totalDebit += value;  // Can exceed int128.max if value is large enough
```

The property `property_account_totalDebit_and_totalCredit_leq_max_int128` correctly catches this:

```solidity
// Properties.sol:178-180
lte(totalDebit, uint128(type(int128).max), "totalDebit is greater than max int128");
lte(totalCredit, uint128(type(int128).max), "totalCredit is greater than max int128");
```

### Category B Impact

The Centrifuge Hub uses double-entry bookkeeping where `totalDebit` and `totalCredit` are stored as `uint128` but are semantically used in signed arithmetic contexts (e.g., computing account value as `totalDebit - totalCredit` or vice versa). If either exceeds `int128.max`, the signed conversion would silently overflow, producing incorrect accounting results.

### Category B Assessment

Severity: Low

- `updateHoldingAmount` requires privileged caller (gateway/admin) — not externally exploitable
- The accounting system assumes values fit in int128 for signed arithmetic
- The property correctly identifies a missing validation gap
- Recommendation: Add `require(amount <= uint128(type(int128).max))` in `updateHoldingAmount`

---

## Category C: `accountValue increased` (1/20 failures)

### Category C Reproducer

```solidity
// CryticToFoundry.sol:289-294
function test_echidna_decrease_valuation_increases_accountValue() public {
    shortcut_create_pool_and_holding(6, 1, 2, true);
    hub_addShareClass_clamped(0, 1);
    hub_updateHoldingAmount_clamped(0, 0, 0, 1, 2002461553125679683);
    hub_updateHoldingValue_clamped(0, 0);
    property_decrease_valuation_no_increase_in_accountValue();
}
```

### Category C Foundry Reproduction

```text
[FAIL: accountValue increased] test_echidna_decrease_valuation_increases_accountValue()
```

### Category C Root Cause: Property Assertion Too Broad

The ghost variable in BeforeAfter.sol correctly tracks `assetAmountValue` (position [1] of the Holding struct):

```solidity
// BeforeAfter.sol:72 — Holding struct: {assetAmount, assetAmountValue, valuation, isLiability}
(, _before.ghostHolding[poolId][scId][assetId],,) = holdings.holding(poolId, scId, assetId);
//  ^ skips assetAmount   ^ captures assetAmountValue
```

The property then checks ALL 6 account types:

```solidity
// Properties.sol:186-208
function property_decrease_valuation_no_increase_in_accountValue() public {
    ...
    if(_before.ghostHolding[poolId][scId][assetId] > _after.ghostHolding[poolId][scId][assetId]) {
        // If holding value decreased, check ALL account types
        for(uint8 kind = 0; kind < 6; kind++) {  // Asset, Equity, Gain, Loss, Expense, Liability
            ...
            if(accountValueAfter > accountValueBefore) {
                t(false, "accountValue increased");  // <-- Fires for Loss account
            }
        }
    }
}
```

In double-entry bookkeeping, when holding value decreases:

- Asset account value **decreases** (expected)
- Loss account value **increases** (expected — this is where the loss is recorded)

The property incorrectly asserts that **no** account value should increase when holding value decreases. But by accounting definition, the Loss account must increase to balance the decrease. The property should exclude Loss (and possibly Gain) accounts from this check.

### Category C Fix

```solidity
for(uint8 kind = 0; kind < 6; kind++) {
    // Skip Loss and Gain accounts — their values naturally move inversely
    if(kind == uint8(AccountType.Loss) || kind == uint8(AccountType.Gain)) continue;

    AccountId accountId = holdings.accountId(poolId, scId, assetId, kind);
    ...
}
```

### Category C Assessment

Severity: Property Bug

The underlying protocol behavior (Loss account increasing when holding value decreases) is correct double-entry bookkeeping. The property is overly broad and should only check Asset/Equity accounts.

---

## Category D: `lastUpdate is > latest redeem approval: 0 <= 0` (1/20 failures)

### Category D Reproducer

```solidity
// CryticToFoundry.sol:299-303
function test_echidna_user_mutates_pending_redeem() public {
    shortcut_create_pool_and_update_holding_amount(6, 1, 2, false, 0, 0, 0, 0);
    hub_addShareClass_clamped(0, 1);
    hub_redeemRequest_clamped(0, 0, 1);
    property_user_cannot_mutate_pending_redeem();
}
```

### Category D Foundry Reproduction

```text
[FAIL: lastUpdate is > latest redeem approval: 0 <= 0] test_echidna_user_mutates_pending_redeem()
```

### Category D Root Cause: Property Fires in Initial State

The property `property_user_cannot_mutate_pending_redeem` (Properties.sol:372-394) checks:

```solidity
// If pending changed, then lastUpdate must be > latest redeem approval
if (_before.ghostRedeemRequest[..].pending != _after.ghostRedeemRequest[..].pending) {
    gt(_before.ghostRedeemRequest[..].lastUpdate, _before.ghostEpochId[..].redeem,
       "lastUpdate is > latest redeem approval");
}
```

In the initial state:

- `lastUpdate = 0` (no previous request)
- `redeemEpochId = 0` (no approvals yet)
- A redeem request with `amount = 1` changes `pending` from 0 to 1 (triggering the precondition)
- The assertion `gt(0, 0)` fails because `0 > 0` is false

The property intends to check: "a user should not be able to mutate their pending redeem if their lastUpdate is behind the latest approval epoch." But in the initial state (no prior updates, no approvals), the first redeem request is perfectly valid.

### Category D Fix

Add a precondition to skip the initial state:

```solidity
if (_before.ghostRedeemRequest[scId][assetId][actor].pending != _after.ghostRedeemRequest[scId][assetId][actor].pending) {
    // Skip initial state where neither lastUpdate nor epoch have been set
    if (_before.ghostRedeemRequest[scId][assetId][actor].lastUpdate == 0
        && _before.ghostEpochId[scId][assetId].redeem == 0) continue;

    gt(_before.ghostRedeemRequest[..].lastUpdate, _before.ghostEpochId[..].redeem, ...);
}
```

### Category D Assessment

Severity: Property Bug

The first redeem request in a fresh epoch is valid behavior. The property lacks an initial-state guard.

---

## Category E: `Price not set` (1/20 failures)

### Category E Reproducer

```solidity
// CryticToFoundry.sol:167-169
function test_shortcut_create_pool_and_update_holding_value() public {
    shortcut_create_pool_and_update_holding_value(18, 123, SC_SALT, false);
}
```

### Category E Foundry Reproduction

```text
[FAIL: Price not set] test_shortcut_create_pool_and_update_holding_value()
```

### Category E Root Cause

The shortcut creates a pool and holding, then immediately calls `hub_updateHoldingValue()` without first setting a price via `hub_updateHoldingAmount()` or `updateSharePrice()`. The `updateHoldingValue` function requires a price to compute the new value — when none is set, it reverts with "Price not set".

### Category E Assessment

Severity: Test Harness Issue

This is a test setup problem, not a protocol bug. The shortcut function needs to initialize a price before calling `updateHoldingValue`.

---

## Summary

| Finding | Type | Severity | Action Required |
| --- | --- | --- | --- |
| Category A: 1-indexed vs 0-indexed epoch | Property bug | N/A | Fix assertion in AdminTargets.sol (3 locations) |
| Category B: totalDebit exceeds int128 max | Missing validation | Low | Add bounds check in `updateHoldingAmount` |
| Category C: Loss account increases on value drop | Property bug | N/A | Exclude Loss/Gain from account loop |
| Category D: Property fires in initial state | Property bug | N/A | Add initial-state guard |
| Category E: Price not set in shortcut | Test harness | N/A | Initialize price before `updateHoldingValue` |

### Impact on Fuzzing Campaign

Category A is the most impactful issue — it masks 15 of 20 tests (75%), preventing meaningful property verification for all deposit/cancel/redeem flows. Fixing the epoch comparison alone would likely unblock the entire hub fuzzing campaign, allowing the remaining 14 properties (accounting soundness, yield, equity, gain, loss) to be exercised through full deposit-redeem lifecycle sequences.

The 11 Echidna reproducers are entirely redundant once Category A is fixed — they all trigger the same epoch assertion on trivial inputs (mostly `amount=0`). After the fix, Echidna should be re-run to discover deeper protocol-level issues.
