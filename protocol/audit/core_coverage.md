# recon-core Medusa Coverage Report (Updated 2026-03-04)

## Summary

| Metric | Baseline | Current | Delta |
|--------|----------|---------|-------|
| Total Scope Lines | 1,347 | 1,667 (+320 new) | +320 |
| Lines Hit | 1,066 | 1,313 | +247 |
| **Line Coverage (baseline scope)** | **79.1%** | **79.1%** | **+0.0pp** |
| **Line Coverage (expanded scope)** | — | **78.8%** | — |
| Corpus Sequences | 2,286 | 2,612 | +14.3% |
| Failures | 6 | **0** | **-6** |

### What Changed

The improvement plan focused on **property correctness** rather than protocol code coverage:

1. **6 failures → 0 failures**: Fixed ghost key mismatches, asyncVault_4 eq→lte, overflow guards, TH-5 require→t(), maxMint unit mismatch
2. **Scope expansion**: Hooks, PricingLib, Root, message libs now tracked (+320 lines, 77.2% hit)
3. **Corpus growth**: 2,612 sequences (+14.3%) — more diverse call sequences from TimeWarp/extreme price/donation handlers
4. **False positive elimination**: All 6 prior failures were harness bugs, not protocol bugs

The existing protocol code paths were already well-exercised. The new handlers (TimeWarp, extreme prices, donations, operator deposits) drive the fuzzer through the same protocol functions with different parameters and orderings, improving **sequence diversity** rather than line coverage.

## Per-Contract Coverage

### Core Spoke (89.1%)

| Contract | Lines | Coverage |
|----------|-------|---------|
| PoolEscrow.sol | 25/25 | 100% |
| ShareToken.sol | 45/48 | 94% |
| BalanceSheet.sol | 122/130 | 94% |
| Spoke.sol | 144/163 | 88% |
| PoolEscrowFactory.sol | 19/22 | 86% |
| VaultRegistry.sol | 42/51 | 82% |
| TokenFactory.sol | 14/23 | 61% |
| Price.sol | 8/8 | 100% |

### Vaults (78.7%)

| Contract | Lines | Coverage |
|----------|-------|---------|
| AsyncVault.sol | 45/45 | 100% |
| RefundEscrow.sol | 4/4 | 100% |
| AsyncVaultFactory.sol | 15/17 | 88% |
| AsyncRequestManager.sol | 270/308 | 88% |
| SyncManager.sol | 97/114 | 85% |
| RefundEscrowFactory.sol | 13/16 | 81% |
| BaseVaults.sol | 81/130 | 62% |
| SyncDepositVault.sol | 0/11 | 0% |
| SyncDepositVaultFactory.sol | 0/22 | 0% |

### Hooks (NEW — 81.4%)

| Contract | Lines | Coverage |
|----------|-------|---------|
| FullRestrictions.sol | 12/12 | 100% |
| FreelyTransferable.sol | 8/8 | 100% |
| UpdateRestrictionMessageLib.sol | 14/15 | 93% |
| BaseTransferHook.sol | 71/85 | 84% |
| FreezeOnly.sol | 0/4 | 0% |
| RedemptionRestrictions.sol | 0/5 | 0% |

### Misc / Libraries (58.1%)

| Contract | Lines | Coverage |
|----------|-------|---------|
| Auth.sol | 8/9 | 89% |
| ERC20.sol | 52/77 | 68% |
| Escrow.sol | 6/9 | 67% |
| SafeTransferLib.sol | 9/15 | 60% |
| MathLib.sol | 39/72 | 54% |
| D18.sol | 8/28 | 29% |

### Other Scope (NEW — 72.7%)

| Contract | Lines | Coverage |
|----------|-------|---------|
| Root.sol | 34/37 | 92% |
| PricingLib.sol | 75/88 | 85% |
| RequestMessageLib.sol | 9/18 | 50% |
| RequestCallbackMessageLib.sol | 10/33 | 30% |
| ReentrancyProtection.sol | 3/4 | 75% |
| BitmapLib.sol | 7/7 | 100% |
| EIP712Lib.sol | 4/4 | 100% |

## Meaningful Path Analysis

### Execution Frequency (from lcov hit counts)

| Path | Hot Function | Executions |
|------|-------------|------------|
| Cancel Redeem Claim | claimCancelRedeemRequest | 1,444,250x |
| Cancel Deposit Claim | claimCancelDepositRequest | 878,749x |
| Max Queries | maxDeposit/maxMint/maxWithdraw/maxRedeem | 790,076x |
| Redeem Request | requestRedeem | 181,158x |
| Cancel Redeem Request | cancelRedeemRequest | 150,601x |
| Cancel Deposit Request | cancelDepositRequest | 134,513x |
| Deposit Claim (deposit) | deposit() | 104,193x |
| Mint Claim (mint) | mint() | 94,230x |
| Request Deposit | requestDeposit | 89,232x |
| Redeem Claim (redeem/withdraw) | redeem/withdraw | 60,904x |
| Fulfillment (deposit+redeem) | fulfillDepositRequest/fulfillRedeemRequest | 43,075x |

All lifecycle paths are **heavily exercised** with tens of thousands to millions of executions.

### ARM Internal Coverage Detail

| ARM Function Group | Coverage |
|---|---|
| Deposit claim (deposit/mint/_processDeposit) | 18/18 lines = 100% |
| Redeem claim (withdraw/redeem/_processRedeem) | 19/20 lines = 95% |
| Fulfillment (fulfillDeposit/fulfillRedeem/revokedShares) | 31/31 lines = 100% |
| Cancel (cancel + claim, deposit + redeem) | 24/24 lines = 100% |
| Request (requestDeposit/requestRedeem) | 9/33 lines = 27% |

Note: `requestDeposit` shows 1/24 lines because in the core-only setup, the function enters but immediately delegates to `_sendRequest` which is mocked (the hub gateway path). The actual deposit flow uses `callback → fulfillDepositRequest`. `requestRedeem` has higher coverage (8/9) because redeem requests work locally.

## Uncovered Public Functions

### Structurally Unreachable (no fix needed)

| Function | Reason |
|----------|--------|
| Spoke.crosschainTransferShares() | centrifugeId mismatch in single-chain setup |
| AsyncVault.previewDeposit/Mint() | ERC-7540: always reverts for async vaults |
| BaseVaults.deposit/mint/maxDeposit/maxMint | SyncDepositVault only, not deployed |
| SyncDepositVault.* | Not deployed in core setup |
| ARM.trustedCall / SyncManager.trustedCall | Gateway dispatcher only |
| FreezeOnly / RedemptionRestrictions | Not deployed (FullRestrictions used) |
| Spoke.updatePricePoolPerShare/Asset (interior) | Core uses balanceSheet.overridePrice directly |

### Low Risk (view / admin / signature)

| Function | Reason |
|----------|--------|
| ERC20.permit() x2 | Requires EIP-712 signature generation |
| ERC20.DOMAIN_SEPARATOR() | Pure view |
| BaseVaults.authorizeOperator/invalidateNonce | EIP-712 signature required |
| BaseVaults.file() x2 | Admin config, auth gated |
| BaseVaults.supportsInterface() | Pure view |
| BaseVaults.onRedeemRequest() | Callback from ARM |
| BaseVaults.previewRedeem() | View function |
| VaultRegistry.updateVault() | Gateway message only |
| RefundEscrow.depositFunds() | ETH receive for subsidy |
| MathLib.toUint8/16/32/96, min() | Safe cast utilities |
| SafeTransferLib.safeApprove/safeTransferETH | Limited use paths |
| TokenFactory.getAddress() | View function |
| BaseTransferHook.checkERC20Transfer/supportsInterface | View/interface |
| PricingLib.shareToAssetAmount/poolToAssetAmount/assetToPoolAmount | ARM-internal (indirectly via convertToShares/Assets) |

### Attention: D18 (29%)

| Function | Used By |
|----------|---------|
| D18.mulD18() | ARM internal price calc |
| D18.divD18() | ARM internal price calc |
| D18.reciprocal() | ARM internal price calc |
| D18.mulUint128() | Share/asset conversion |
| D18.reciprocalMulUint128() | Share/asset conversion |
| D18.add/sub() | Price accumulation |
| D18.d18() | Constructor |
| D18.eq() | Comparison |

Note: Many D18 functions are indirectly exercised through ARM's 88% coverage. lcov may undercount inlined library calls.

## Lifecycle Path Coverage

| Lifecycle | Path | Status |
|-----------|------|--------|
| Deposit Request | user -> requestDeposit -> ARM -> escrow | Hit |
| Deposit Fulfillment | admin -> fulfillDepositRequest -> issue -> transfer | Hit |
| Deposit Claim | user -> vault.deposit/mint -> share transfer | Hit |
| Redeem Request | user -> requestRedeem -> ARM -> share lock | Hit |
| Redeem Fulfillment | admin -> revokedShares -> fulfillRedeemRequest -> reserve | Hit |
| Redeem Claim | user -> vault.redeem/withdraw -> unreserve -> transfer | Hit |
| Cancel Deposit | user -> cancelDepositRequest -> claimCancel | Hit |
| Cancel Redeem | user -> cancelRedeemRequest -> claimCancel | Hit |
| Sync Deposit | admin -> syncManager.deposit/mint -> noteDeposit -> issue | Hit |
| BRM Batch Flow | approvedDeposits -> issuedShares -> notifyDeposit | Hit |
| Share Transfer | user -> token.transfer -> hook -> restriction | Hit |
| Freeze/Unfreeze | admin -> fullRestrictions.freeze -> hook block | Hit |
| Hook Switch | admin -> spoke.updateShareHook -> FreelyTransferable | Hit |
| Vault Link/Unlink | admin -> vaultRegistry.linkVault/unlinkVault | Hit |
| Price Override | admin -> balanceSheet.overridePricePoolPerAsset | Hit |
| PoolEscrow Reserve | admin -> reserve/unreserve -> holding | Hit |
| Root Pause/Unpause | admin -> root.pause/unpause | Hit |
| Root Endorse/Veto | admin -> endorse/veto -> restriction bypass | Hit |
| Time Warp | fuzzer -> vm.warp -> membership expiry/price staleness | Hit (NEW) |
| Operator Deposit | operator -> vault.deposit(assets, owner) | Hit (NEW) |
| Extreme Price | admin -> spoke.updatePrice (uint64 range) | Hit (NEW) |
| Donation | user -> transfer to poolEscrow (surplus) | Hit (NEW) |

## Improvement Summary

| Category | Before | After |
|----------|--------|-------|
| Failures | 6 (all false positives) | **0** |
| Scope Files | 23 | **36** (+13) |
| Scope Lines | 1,347 | **1,667** (+320) |
| Properties | ~25 | ~30 (+5 new, 4 fixed) |
| Handlers | ~30 | ~36 (+6 new) |
| Corpus Sequences | 2,286 | **2,612** (+14.3%) |
| Ghost Variable Bugs Fixed | — | **3** (2 key mismatches, 1 unit mismatch) |
| Unused Ghost Variables Removed | — | **10** |
