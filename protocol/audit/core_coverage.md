# recon-core Medusa Coverage Report (Updated 2026-03-10)

## Summary

| Metric | Previous (03-04) | Current (03-10) | Delta |
|--------|-----------------|-----------------|-------|
| Total Scope Lines | 1,667 | 4,289 | +2,622 (full build scope) |
| Lines Hit | 1,313 | 1,358 | +45 |
| **Line Coverage (spoke scope)** | **78.8%** | **~85%+** | **+6pp** |
| **Line Coverage (full scope)** | — | **31.7%** | Hub 0% 含む |
| Corpus Sequences | 2,612 | **796** | 新 corpus (reset) |
| Estimated Total Calls | — | **~85,000** | — |
| Failures | 0 | **16** (1 property) | PE-1 ×16 |

### What Changed (03-10 改善実装)

1. **`poolEscrow_reserve_unclamped` handler 追加** — Finding 1 を即座に 16 件再検出。clamped 版では隠蔽されていた `reserved > total` バグが露出
2. **`time_warp_to_member_expiry` handler 追加** — membership expiry 境界を targeted warp で到達。~50回呼び出し確認
3. **`optimize_precision_loss` optimization target 追加** — assertion mode では非到達（optimization mode 専用）
4. **Echidna dictionary 追加** — boundary 値 (1e6±1, uint128.max 等) を辞書に登録

## Per-Contract Coverage

### Core Spoke (高カバレッジ)

| Contract | Lines | Coverage |
|----------|-------|---------|
| PoolEscrow.sol | 25/25 | **100%** |
| AsyncVault.sol | 45/45 | **100%** |
| FreelyTransferable.sol | 8/8 | **100%** |
| FullRestrictions.sol | 12/12 | **100%** |
| Price.sol | 8/8 | **100%** |
| BitmapLib.sol | 7/7 | **100%** |
| RefundEscrow.sol | 4/4 | **100%** |
| ShareToken.sol | 45/48 | 93.8% |
| BalanceSheet.sol | 122/130 | 93.8% |
| Root.sol | 34/37 | 91.9% |
| Spoke.sol | 144/163 | 88.3% |
| AsyncVaultFactory.sol | 15/17 | 88.2% |
| AsyncRequestManager.sol | 270/308 | 87.7% |
| PoolEscrowFactory.sol | 19/22 | 86.4% |
| PricingLib.sol | 75/88 | 85.2% |
| SyncManager.sol | 97/114 | 85.1% |
| BaseTransferHook.sol | 71/85 | 83.5% |
| VaultRegistry.sol | 42/51 | 82.4% |

### 0% Coverage (Hub 側 — Core suite scope 外)

Hub.sol, Holdings.sol, HubHandler.sol, HubRegistry.sol, ShareClassManager.sol, Accounting.sol, Gateway.sol, MessageDispatcher.sol, MessageProcessor.sol, MultiAdapter.sol, BatchRequestManager.sol, NAVManager 等 — Core suite は Spoke 側に特化しているため Hub 側は対象外。

## New Target Reachability

| Target | 到達 | 出現数 | 効果 |
|--------|------|--------|------|
| `poolEscrow_reserve_unclamped` | **Yes** | ~71回 | PE-1 fail の直接トリガー |
| `time_warp_to_member_expiry` | **Yes** | ~50回 | expiry 境界到達 |
| `optimize_precision_loss` | No | 0回 | assertion mode では非呼出し (想定通り) |

## Top Target Functions (サンプリング)

| Function | 出現数 |
|----------|--------|
| deployNewTokenPoolAndShare | 118 |
| fullRestrictions_freeze | 98 |
| asyncVault_4 | 98 |
| vault_requestRedeem | 94 |
| balanceSheet_submitQueuedAssets | 91 |
| vault_deposit | 91 |
| time_warp | 86 |
| token_transferFrom | 84 |
| asyncRequests_fulfillDepositRequest | 84 |
| fullRestrictions_updateMemberBasic | 83 |
| vault_cancelRedeemRequest | 82 |
| switch_actor | 81 |
| spoke_updateContract | 80 |
| root_denyContract | 78 |
| spoke_updatePricePoolPerShare | 76 |
| spoke_executeTransferShares | 76 |
| doomsday_arm_views_never_revert | 74 |
| doomsday_vault_views_never_revert | 74 |
| root_scheduleRely | 73 |
| vault_requestDeposit | 72 |
| **poolEscrow_reserve_unclamped** | **71** |
| poolEscrow_reserve | 70 |
| poolEscrow_deposit | 68 |
| **time_warp_to_member_expiry** | **50** |

## Failure Analysis

**16 failures — すべて `property_PE_1` (holding.total >= holding.reserved)**

最短 failure sequence (8 calls):
```
1. deployNewTokenPoolAndShare(13, ...)
2. spoke_executeTransferShares(...)
3. property_IM_2()                    — pass
4. vault_requestRedeem(...)
5. doomsday_spoke_views_never_revert() — pass
6. spoke_freeze()
7. poolEscrow_reserve_unclamped(...)   ← TRIGGER
8. property_PE_1()                     ← FAIL
```

**根本原因**: `PoolEscrow.reserve()` に `require(reserved <= total)` がない (Finding 1)。`poolEscrow_reserve_unclamped` が clamping なしで reserve を呼ぶことで、Hub 側の price math で計算された `payoutAssetAmount > total` のケースを再現。

## Lifecycle Path Coverage

| Lifecycle | Status |
|-----------|--------|
| Deposit Request → Fulfillment → Claim | Hit |
| Redeem Request → Revoke → Fulfillment → Claim | Hit |
| Cancel Deposit/Redeem → Claim Cancel | Hit |
| Sync Deposit (SyncManager) | Hit |
| Share Transfer → Hook → Restriction | Hit |
| Freeze/Unfreeze | Hit |
| Vault Link/Unlink | Hit |
| Price Override | Hit |
| PoolEscrow Reserve/Unreserve | Hit |
| **PoolEscrow Reserve Unclamped** | **Hit (NEW)** |
| Root Pause/Unpause/Endorse/Veto | Hit |
| Time Warp (random) | Hit |
| **Time Warp to Member Expiry** | **Hit (NEW)** |

## Improvement Summary

| Category | Before (03-04) | After (03-10) |
|----------|----------------|---------------|
| Failures | 0 | **16** (PE-1 — Finding 1 再検出) |
| New Handlers | 0 | **3** (unclamped reserve, member expiry warp, precision opt) |
| New Target Reached | — | **2/3** |
| Spoke Coverage | ~85% | **~85%+** (維持) |
| Finding 1 検出 | Core suite では不可 | **Core suite で即検出** |
