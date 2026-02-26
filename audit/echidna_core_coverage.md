# Echidna Core Coverage Analysis

## Overview

- Config: `echidna_core.yaml` --- Contract: `CryticCoreTester`, mode: assertion, seqLen: 200, testLimit: 100M
- LCOV: `echidna_core/covered.1772044996.lcov` (latest of 3 runs) --- 19,392 instrumented lines across 200+ files
- Corpus: **114 coverage sequences** in `echidna_core/coverage/`
- Reproducers: **0 failure sequences** --- no assertion violations detected

## Overall Coverage

| Scope | Lines Hit | Lines Total | Coverage |
| --- | --- | --- | --- |
| **All instrumented** | 686 | 19,392 | 3.5% |
| **src/spoke/ (primary target)** | 151 | 594 | **25.4%** |
| **src/vaults/ (primary target)** | 28 | 850 | **3.3%** |
| **src/hooks/** | 25 | 177 | **14.1%** |
| **src/ (all protocol)** | 212 | 4,373 | 4.8% |
| **test/vaults/fuzzing/recon-core/** | 399 | 3,478 | 11.5% |

The raw 3.5% is misleading --- the core suite targets only Spoke+Vaults contracts. Hub-side code is intentionally mocked via `MockHub` and correctly shows near-0% coverage. However, even within the target scope, coverage is very low: **src/spoke/ at 25.4% and src/vaults/ at 3.3%** indicate that the fuzzer struggles to exercise meaningful vault operation paths.

## Module Breakdown

| Module | Hit/Total | Coverage | Notes |
| --- | --- | --- | --- |
| src/spoke/ | 151/594 | **25.4%** | Spoke, BalanceSheet, ShareToken, Escrow |
| src/vaults/ | 28/850 | **3.3%** | AsyncRequestManager, SyncRequestManager --- BaseVaults/AsyncVault at 0% |
| src/hooks/ | 25/177 | **14.1%** | FullRestrictions freeze/unfreeze covered, transfer hooks 0% |
| src/misc/ | 7/438 | 1.6% | Minimal library usage (CastLib, MathLib) |
| src/common/ | 1/1,385 | 0.1% | Intentionally mocked (Gateway, MessageLib) |
| src/hub/ | 1/929 | 0.1% | Intentionally mocked via MockHub |

## Per-File Coverage (Target Protocol Files)

### src/spoke/ --- Spoke-Side Contracts

| File | Hit/Total | Coverage | Assessment |
| --- | --- | --- | --- |
| [Spoke.sol](src/spoke/Spoke.sol) | 91/243 | **37.4%** | Moderate --- setup/registration good, transfer/deploy/link mostly uncovered |
| [BalanceSheet.sol](src/spoke/BalanceSheet.sol) | 10/165 | **6.1%** | Critical gap --- almost all core operations at 0% |
| [ShareToken.sol](src/spoke/ShareToken.sol) | 9/61 | **14.8%** | Only transferFrom and updateVault partially covered |
| [Escrow.sol](src/spoke/Escrow.sol) | 7/43 | **16.3%** | authTransferTo 43%, pendingAuthTransferTo 33%, rest 0% |
| [PoolEscrow.sol](src/spoke/PoolEscrow.sol) | 11/24 | **45.8%** | Reasonably good --- setup by vault factory |
| [TokenFactory.sol](src/spoke/factories/TokenFactory.sol) | 13/29 | **44.8%** | newShareToken exercised, other factories not |
| [PoolEscrowFactory.sol](src/spoke/factories/PoolEscrowFactory.sol) | 10/29 | **34.5%** | newPoolEscrow exercised during deploy |

### src/vaults/ --- Vault-Side Contracts

| File | Hit/Total | Coverage | Assessment |
| --- | --- | --- | --- |
| [AsyncRequestManager.sol](src/vaults/AsyncRequestManager.sol) | 12/233 | **5.2%** | requestDeposit 7%, file() 86%, everything else 0% |
| [SyncRequestManager.sol](src/vaults/SyncRequestManager.sol) | 9/116 | **7.8%** | file() 83%, setValuation 33%, rest 0% |
| [BaseRequestManager.sol](src/vaults/BaseRequestManager.sol) | 7/99 | **7.1%** | Only file() and addVault partially covered |
| [AsyncVault.sol](src/vaults/AsyncVault.sol) | 0/52 | **0.0%** | Completely uncovered |
| [BaseVaults.sol](src/vaults/BaseVaults.sol) | 0/147 | **0.0%** | Completely uncovered |

### src/hooks/ --- Transfer Restrictions

| File | Hit/Total | Coverage | Assessment |
| --- | --- | --- | --- |
| [FullRestrictions.sol](src/hooks/FullRestrictions.sol) | 18/58 | **31.0%** | freeze/unfreeze/updateMember covered, onERC20Transfer 0% |
| [ERC20.sol](src/misc/ERC20.sol) | 10/86 | **11.6%** | file() 80%, everything else near 0% |

## Function-Level Coverage: Spoke.sol (37.4%)

### Fully Covered (100%)

| Function | Lines | Description |
| --- | --- | --- |
| `addPool` | 3/3 | Pool creation |
| `registerAsset` (partial) | 8/10 | Asset registration --- 80% |
| `addShareClass` (partial) | 8/10 | Share class + token deployment --- 80% |

### Partially Covered

| Function | Coverage | Gap |
| --- | --- | --- |
| `registerAsset` | 80% (8/10) | Error path uncovered |
| `addShareClass` | 80% (8/10) | Error path uncovered |
| `deployVault` | 33% (2/6) | Only initial deploy covered, not all branches |
| `linkVault` | 33% | Partial link path |
| `updatePricePoolPerShare` | 50% | Set but not all branches |
| `updatePricePoolPerAsset` | 50% | Set but not all branches |
| `updateRestriction` | 40% | Only freeze/unfreeze paths |
| `updateShareMetadata` | 33% | Partial |

### Completely Uncovered (0%) --- Critical Functions

| Function | Lines | Why Uncovered |
| --- | --- | --- |
| `transferShares` | 8 | PoolManagerTargets: `spoke_handleTransferShares` commented out |
| `linkToken` | 5 | No target function |
| `updateShareHook` | 4 | No target function |
| `updateVault` | 8 | No target function (only `deployVault`/`linkVault`) |
| `unlinkVault` | 5 | `removeVault_clamped` exists but apparently never reached |
| `handleTransferShares` | 6 | Commented out in PoolManagerTargets |
| `submitQueuedAssets` | 6 | BalanceSheet queue --- never exercised |
| `submitQueuedShares` | 6 | BalanceSheet queue --- never exercised |
| `file` (some branches) | 5/10 | Only 50% of config paths |

## Function-Level Coverage: BalanceSheet.sol (6.1%)

### Critical Gaps

| Function | Coverage | Impact |
| --- | --- | --- |
| `file()` | 83% (5/6) | Only admin config partially covered |
| `withdraw` | 11% (1/9) | Barely entered |
| `deposit` | 0% (0/7) | Core deposit flow completely untested |
| `issue` | 0% (0/8) | Share issuance completely untested |
| `revoke` | 0% (0/8) | Share revocation completely untested |
| `noteDeposit` | 0% (0/5) | Deposit notification untested |
| `submitQueuedAssets` | 0% (0/12) | Queue mechanism untested |
| `submitQueuedShares` | 0% (0/12) | Queue mechanism untested |
| `overridePricePoolPerShare` | 0% (0/3) | Price override untested |
| `resetPricePoolPerShare` | 0% (0/3) | Price reset untested |

The BalanceSheet is central to the Spoke-side architecture --- it handles share issuance, revocation, deposit/withdrawal, and the queue mechanism. At 6.1%, virtually none of these critical paths have been exercised by the fuzzer.

## Function-Level Coverage: AsyncRequestManager.sol (5.2%)

| Function | Coverage | Impact |
| --- | --- | --- |
| `file()` | 86% (6/7) | Config setup covered |
| `requestDeposit` | 7% (1/14) | Only entry point touched, core logic 0% |
| `requestRedeem` | 0% (0/12) | Completely untested |
| `fulfillDepositRequest` | 0% (0/22) | Epoch fulfillment untested |
| `fulfillRedeemRequest` | 0% (0/20) | Epoch fulfillment untested |
| `cancelDepositRequest` | 0% (0/8) | Cancel flow untested |
| `cancelRedeemRequest` | 0% (0/8) | Cancel flow untested |
| `deposit` (claim) | 0% (0/12) | Deposit claim untested |
| `mint` (claim) | 0% (0/12) | Mint claim untested |
| `redeem` (claim) | 0% (0/12) | Redeem claim untested |
| `withdraw` (claim) | 0% (0/12) | Withdraw claim untested |
| `maxDeposit` | 0% (0/4) | View function untested |
| `maxMint` | 0% (0/4) | View function untested |
| `maxRedeem` | 0% (0/4) | View function untested |
| `maxWithdraw` | 0% (0/4) | View function untested |

Despite `VaultCallbackTargets` containing `asyncRequests_fulfillDepositRequest` and `asyncRequests_fulfillRedeemRequest`, these never meaningfully reach the AsyncRequestManager because the prerequisite `requestDeposit` barely completes (7%). The cancel fulfillment callbacks are commented out entirely.

## Property Coverage

### Properties.sol --- 18+ Active Properties

| Property | Type | Status |
| --- | --- | --- |
| `property_sentinel_token_balance` | Sentinel | Partially reached --- early-returns when token not deployed |
| `property_global_1` | Accounting | Exercisable only after fulfilled deposits (sumOfClaimedDeposits) |
| `property_global_2` | Accounting | Exercisable only after fulfilled redeems (sumOfClaimedRedemptions) |
| `property_global_2_inductive` | Inductive | Requires pendingRedeemRequest decrease --- rarely triggered |
| `property_global_3` | Total supply | Exercisable --- tracks mints/burns/transfers |
| `property_global_4` | Dust check | Exercisable --- checks system addresses have 0 balance |
| `property_global_5` | Cancel deposit | Exercisable only after fulfilled cancel deposits |
| `property_global_5_inductive` | Inductive | Requires claimableCancelDepositRequest decrease |
| `property_global_6` | Cancel redeem | Exercisable only after fulfilled cancel redeems |
| `property_global_6_inductive` | Inductive | Requires claimableCancelRedeemRequest decrease |
| `property_tt_2` | Token supply | Always exercisable --- sum of balances <= totalSupply |
| `property_IM_1` | Price bounds | Deposit price bounds check |
| `property_IM_2` | Price bounds | Redeem price bounds check |
| `property_E_1` | Escrow balance | Asset escrow accounting --- requires fulfilled requests |
| `property_E_2` | Escrow balance | Share escrow accounting --- requires fulfilled requests |
| `property_E_3` | Escrow solvency | maxWithdraw sum <= escrow balance |
| `property_E_4` | Escrow solvency | maxMint sum <= escrow share balance |
| `property_totalAssets_solvency` | Solvency | totalAssets <= actual assets |
| `property_totalAssets_insolvency_only_increases` | Monotonicity | Insolvency delta monotonic |
| `optimize_totalAssets_solvency` | Optimization | Maximize insolvency difference |

### AsyncVaultCentrifugeProperties --- 17 Properties

| Property | Status |
| --- | --- |
| `asyncVault_3` through `asyncVault_9_*` (13 overrides) | All guarded by `_centrifugeSpecificPreChecks` --- require vault + token + restrictions + asset deployed |
| `asyncVault_maxDeposit` | Requires `maxDeposit > 0` --- needs fulfilled deposit requests |
| `asyncVault_maxMint` | Requires `maxMint > 0` --- needs fulfilled deposit requests |
| `asyncVault_maxWithdraw` | Requires `maxWithdraw > 0` --- needs fulfilled redeem requests |
| `asyncVault_maxRedeem` | Requires `maxRedeem > 0` --- needs fulfilled redeem requests |

**Assessment**: Most properties have **vacuous coverage** --- they either early-return (vault/token not set) or their `require` preconditions are never met because the underlying vault operations never complete. The few that are always exercisable (`property_tt_2`, `property_global_3`, `property_global_4`) provide limited value without meaningful vault state changes.

## Target Functions Coverage

### Target File Harness Coverage

| Target File | Line Coverage | Assessment |
| --- | --- | --- |
| [GatewayMockTargets.sol](test/vaults/fuzzing/recon-core/targets/GatewayMockTargets.sol) | 70.6% | Well exercised --- deploy, register, price updates |
| [ManagerTargets.sol](test/vaults/fuzzing/recon-core/targets/ManagerTargets.sol) | 72.7% | Actor/asset switching, approve, mint |
| [FullRestrictionsTargets.sol](test/vaults/fuzzing/recon-core/targets/FullRestrictionsTargets.sol) | ~60% | freeze/unfreeze/updateMember covered |
| [ShareTokenTargets.sol](test/vaults/fuzzing/recon-core/targets/ShareTokenTargets.sol) | 29.0% | transfer/transferFrom partially exercised |
| [VaultCallbackTargets.sol](test/vaults/fuzzing/recon-core/targets/VaultCallbackTargets.sol) | 7.7% | Barely exercised --- fulfill callbacks rarely reached |
| [VaultTargets.sol](test/vaults/fuzzing/recon-core/targets/VaultTargets.sol) | 8.6% | Very low --- most vault operations fail/revert |
| [PoolManagerTargets.sol](test/vaults/fuzzing/recon-core/targets/PoolManagerTargets.sol) | ~5% | All transfer functions commented out |

### Target Function Reachability

| Target Function | Protocol Functions Exercised | Status |
| --- | --- | --- |
| `deployNewTokenPoolAndShare` | Spoke.registerAsset, addPool, addShareClass, deployVault, linkVault | Working --- core setup path |
| `spoke_registerAsset` | Spoke.registerAsset | Working |
| `spoke_addPool` | Spoke.addPool | Working |
| `spoke_addShareClass` | Spoke.addShareClass, ShareToken deployment | Working |
| `deployVault` | Spoke.deployVault, linkVault | Working |
| `spoke_updatePricePoolPerShare` | Spoke.updatePricePoolPerShare, updatePricePoolPerAsset | Working |
| `spoke_updateMember` | Spoke.updateRestriction -> FullRestrictions | Working |
| `spoke_freeze` / `spoke_unfreeze` | FullRestrictions.freeze/unfreeze | Working |
| `vault_requestDeposit` | AsyncVault.requestDeposit -> AsyncRequestManager | Mostly reverts |
| `vault_requestRedeem` | AsyncVault.requestRedeem -> AsyncRequestManager | Mostly reverts |
| `vault_deposit` (claim) | AsyncVault.deposit -> AsyncRequestManager.deposit | Almost never reached |
| `vault_mint` (claim) | AsyncVault.mint -> AsyncRequestManager.mint | Almost never reached |
| `vault_redeem` (claim) | AsyncVault.redeem -> AsyncRequestManager.redeem | Almost never reached |
| `vault_withdraw` (claim) | AsyncVault.withdraw -> AsyncRequestManager.withdraw | Almost never reached |
| `vault_cancelDepositRequest` | AsyncVault.cancelDepositRequest | Almost never reached |
| `vault_cancelRedeemRequest` | AsyncVault.cancelRedeemRequest | Almost never reached |
| `vault_claimCancelDepositRequest` | AsyncVault.claimCancelDepositRequest | Almost never reached |
| `vault_claimCancelRedeemRequest` | AsyncVault.claimCancelRedeemRequest | Almost never reached |
| `asyncRequests_fulfillDepositRequest` | AsyncRequestManager.fulfillDepositRequest | Requires pending request |
| `asyncRequests_fulfillRedeemRequest` | AsyncRequestManager.fulfillRedeemRequest | Requires pending request |
| `fulfillCancelDepositRequest` | (Commented out) | Not available |
| `fulfillCancelRedeemRequest` | (Commented out) | Not available |
| `token_transfer` | ShareToken.transfer | Partial --- restriction checks work |
| `token_transferFrom` | ShareToken.transferFrom | Partial --- restriction checks work |

## Critical Coverage Gaps

### 1. AsyncVault + BaseVaults: 0% Combined Coverage

The vault contract layer (AsyncVault.sol, BaseVaults.sol) has **zero line coverage**. This means:

- `requestDeposit()` --- SafeTransferLib.safeTransferFrom never executed
- `requestRedeem()` --- IShareToken.authTransferFrom never executed
- `deposit()` / `mint()` / `redeem()` / `withdraw()` --- claim functions never executed
- `cancelDepositRequest()` / `cancelRedeemRequest()` --- cancel flows never executed
- All event emissions (`DepositRequest`, `RedeemRequest`, `Deposit`, `Withdraw`) --- never tested

**Root cause**: The vault functions are called through VaultTargets.sol but consistently revert. The `vault_requestDeposit` handler (VaultTargets.sol:33-87) attempts `vault.requestDeposit(assets, to, _getActor())` which requires:

1. Sufficient `IERC20(asset).balanceOf(owner) >= assets` (clamped --- OK)
2. `asyncManager().requestDeposit(this, assets, controller, owner, msg.sender)` to succeed
3. This requires the vault to be linked, the investor to pass restriction checks

The chain of dependencies is fragile --- any single requirement failure causes a silent revert caught by the `try/catch` in VaultTargets.

### 2. BalanceSheet: 6.1% --- Core Accounting Untested

The BalanceSheet manages:

- Share issuance (`issue`) --- 0%
- Share revocation (`revoke`) --- 0%
- Deposit notation (`noteDeposit`) --- 0%
- Withdrawal (`withdraw`) --- 11%
- Queue mechanism (`submitQueuedAssets`, `submitQueuedShares`) --- 0%

This means the Spoke-side accounting for share lifecycle is entirely untested.

### 3. Cancel Fulfillment Callbacks: Commented Out

In VaultCallbackTargets.sol, both `asyncRequests_fulfillCancelDepositRequest` and `asyncRequests_fulfillCancelRedeemRequest` are entirely commented out (lines 169-280). This means:

- The cancel-and-claim lifecycle is never completed
- Properties `property_global_5`, `property_global_5_inductive`, `property_global_6`, `property_global_6_inductive` can never be meaningfully exercised
- Ghost variables `cancelDepositCurrencyPayout` and `cancelRedeemShareTokenPayout` never accumulate

### 4. Transfer Functions: Commented Out

In PoolManagerTargets.sol, `spoke_handleTransferShares` and `spoke_transferSharesToEVM` are commented out, meaning:

- `Spoke.transferShares` --- 0%
- `Spoke.handleTransferShares` --- 0%
- Ghost variables `incomingTransfers`/`outGoingTransfers` never accumulate
- `property_global_3` (total supply accounting) loses transfer tracking accuracy

### 5. Property Vacuity

Many properties guard with `tokenIsSet`, `assetIsSet`, or `_canCheckProperties()`. While the `deployNewTokenPoolAndShare` function sets up the token/asset/vault, the **underlying state transitions** (fulfilled deposits, redeems, cancellations) rarely happen. This means:

- `property_global_1`: compares `sumOfClaimedDeposits` vs `sumOfFullfilledDeposits` --- both likely near 0
- `property_E_1` / `property_E_2`: escrow balance accounting --- trivially true when no operations complete
- `property_totalAssets_solvency`: `totalAssets` and `actualAssets` are both near 0
- Inductive properties: condition guards (`_before > _after`) almost never trigger

## Corpus Analysis

**114 corpus files** is significantly more than hub's 4, but coverage remains very low. This indicates:

- Echidna found many distinct paths through the **setup and admin functions** (deploy, register, price updates, restrictions)
- The fuzzer is **unable to complete full vault operation lifecycles** --- deposit request -> fulfill -> claim
- Assertion mode with 0 reproducers means the fuzzer found no assertion violations, but this is likely because the assertion-checked code paths are never reached
- The `try/catch` wrappers in VaultTargets.sol silently swallow reverts, preventing the fuzzer from recognizing operation failures as assertion violations

## Comparison with Hub Suite

| Metric | echidna_hub | echidna_core |
| --- | --- | --- |
| Target module coverage | 54.6% | 25.4% (spoke) / 3.3% (vaults) |
| Corpus files | 4 | 114 |
| Reproducers | 11 | 0 |
| Core operation lifecycle | Blocked at deposit (Cat A) | Blocked at request/fulfill chain |
| Property violations | Yes (5 categories) | None detected |
| Properties exercised | 10/14 fully | Most vacuously true |

Despite more corpus files, the core suite achieves lower coverage because:

1. The hub suite has **shortcut functions** that bundle multi-step operations (e.g., `shortcut_deposit_and_claim`), while the core suite relies on Echidna to discover the correct **multi-step sequence** across separate target functions
2. The core suite has a longer dependency chain: deploy -> register -> addPool -> addShareClass -> deployVault -> setPrice -> updateMember -> requestDeposit -> fulfillDeposit -> deposit/mint
3. Silent `try/catch` failures prevent the fuzzer from learning which sequences are productive

## Recommendations

### High Priority

1. **Add shortcut/guided sequences** --- Create compound target functions similar to hub's `shortcut_deposit_and_claim` that bundle: requestDeposit -> fulfillDepositRequest -> deposit/mint in a single call. This dramatically reduces the sequence length Echidna needs to discover.

2. **Uncomment cancel fulfillment callbacks** --- `asyncRequests_fulfillCancelDepositRequest` and `asyncRequests_fulfillCancelRedeemRequest` in VaultCallbackTargets.sol are commented out. Enabling them would unlock the cancel-claim lifecycle and exercise properties global_5/global_6.

3. **Add assertion on revert in vault operations** --- The `try/catch` in VaultTargets.sol silently catches all reverts. Consider logging or tracking revert rates so the team can identify when the fuzzer is stuck (e.g., if `vault_requestDeposit` reverts 99% of the time).

### Medium Priority

1. **Add BalanceSheet target functions** --- Direct targets for `balanceSheet.issue()`, `balanceSheet.deposit()`, `balanceSheet.noteDeposit()` to exercise the accounting paths independently of the vault layer.

2. **Uncomment transfer functions** --- Re-enable `spoke_handleTransferShares` and `spoke_transferSharesToEVM` in PoolManagerTargets.sol to exercise the transfer paths and properly track `incomingTransfers`/`outGoingTransfers` for property_global_3.

3. **Add Spoke.updateVault target** --- Currently no target for `updateVault`, meaning vault replacement/upgrade paths are untested.

### Low Priority

1. **Increase seqLen for lifecycle testing** --- After adding shortcuts, the current `seqLen: 200` should be sufficient. Without shortcuts, the fuzzer may need much longer sequences to discover the full lifecycle.

2. **Add SyncVault testing** --- SyncRequestManager.sol has 7.8% coverage and no sync vault is deployed. Consider deploying a `SyncDepositAsyncRedeemVault` alongside the async vault to exercise the sync deposit path.

3. **Track and report property vacuity** --- Add sentinel checks that flag when properties are being "tested" but with trivial inputs (all zeros). This helps distinguish between "property holds" and "property was never meaningfully checked".

## Summary

| Metric | Value |
| --- | --- |
| Target module (src/spoke/) coverage | **25.4%** |
| Target module (src/vaults/) coverage | **3.3%** |
| AsyncVault.sol | **0.0%** (completely uncovered) |
| BaseVaults.sol | **0.0%** (completely uncovered) |
| BalanceSheet.sol | **6.1%** (critical gap) |
| AsyncRequestManager.sol | **5.2%** (critical gap) |
| Spoke.sol | **37.4%** (moderate --- setup good, operations uncovered) |
| FullRestrictions.sol | **31.0%** (freeze/unfreeze only) |
| Active properties meaningfully exercised | ~3-4 out of 35+ (most vacuously true) |
| Corpus sequences | 114 (good exploration, but confined to setup paths) |
| Biggest blocker | Multi-step vault lifecycle sequence discovery |
| Commented-out targets | 4 functions (cancel fulfills, transfers) |
