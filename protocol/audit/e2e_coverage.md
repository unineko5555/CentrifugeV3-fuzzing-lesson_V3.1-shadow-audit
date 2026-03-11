# E2E Medusa Coverage Report

**Corpus**: 790 sequences / 66,708 calls | **Failures**: 0/39 properties | **Overall (protocol src)**: 55.6% (2,621/4,718 lines)

## Key Achievement

**全6ライフサイクルパスが完全カバー** — Hub↔Spoke 境界を横断する全主要フローが実行確認済み。

| Lifecycle Path | Status | Steps |
|---|---|---|
| Deposit (full cycle) | 10/10 | request → approve → issue → notify → fulfill → claim |
| Redeem (full cycle) | 10/10 | request → approve → revoke → reserve → notify → fulfill → claim |
| Cancel Deposit | 4/4 | cancel → hub process → force cancel → claim refund |
| Cancel Redeem | 4/4 | cancel → hub process → force cancel → claim shares |
| Price Propagation | 8/8 | hub updateSharePrice → notifySharePrice → spoke read → balanceSheet override |
| NAV & Accounting | 9/9 | initNetwork → initHolding → updateValue → closeGainLoss → sync |
| SyncManager | 6/6 | setValuation → setMaxReserve → convertToShares/Assets → maxDeposit → pricePoolPerShare |

## Per-Contract Coverage (src/ files with >0 lines)

### Hub Side

| Contract | Hit/Total | Coverage |
|---|---|---|
| Accounting.sol | 54/56 | **96%** |
| IdentityValuation.sol | 6/7 | **86%** |
| OracleValuation.sol | 17/20 | **85%** |
| BatchRequestManager.sol | 326/385 | **85%** |
| ShareClassManager.sol | 43/55 | **78%** |
| Holdings.sol | 63/83 | **76%** |
| Hub.sol | 135/185 | **73%** |
| NAVManager.sol | 77/111 | **69%** |
| HubRegistry.sol | 33/48 | **69%** |
| QueueManager.sol | 21/32 | **66%** |
| HubHandler.sol | 17/34 | **50%** |

### Spoke Side

| Contract | Hit/Total | Coverage |
|---|---|---|
| PoolEscrowFactory.sol | 19/22 | **86%** |
| ShareToken.sol | 40/48 | **83%** |
| BalanceSheet.sol | 103/130 | **79%** |
| FullRestrictions.sol | 9/12 | **75%** |
| BaseTransferHook.sol | 62/85 | **73%** |
| Spoke.sol | 118/163 | **72%** |
| VaultRegistry.sol | 35/51 | **69%** |
| TokenFactory.sol | 14/23 | **61%** |
| PoolEscrow.sol | 13/25 | **52%** |

### Vaults

| Contract | Hit/Total | Coverage |
|---|---|---|
| RequestCallbackMessageLib.sol | 32/33 | **97%** |
| AsyncVaultFactory.sol | 15/17 | **88%** |
| SyncManager.sol | 70/114 | **61%** |
| AsyncVault.sol | 27/45 | **60%** |
| AsyncRequestManager.sol | 182/308 | **59%** |
| RefundEscrowFactory.sol | 7/16 | **44%** |
| BaseVaults.sol | 43/130 | **33%** |

### Messaging

| Contract | Hit/Total | Coverage |
|---|---|---|
| MessageLib.sol | 177/270 | **66%** |
| MessageProcessor.sol | 110/166 | **66%** |
| Gateway.sol | 84/128 | **66%** |
| GasService.sol | 60/92 | **65%** |
| MultiAdapter.sol | 56/86 | **65%** |
| MessageDispatcher.sol | 88/184 | **48%** |

### Libraries & Types

| Contract | Hit/Total | Coverage |
|---|---|---|
| TransientBytesLib.sol | 28/28 | **100%** |
| TransientArrayLib.sol | 19/19 | **100%** |
| BitmapLib.sol | 7/7 | **100%** |
| EnumerableSet.sol | 23/24 | **96%** |
| UpdateRestrictionMessageLib.sol | 14/15 | **93%** |
| BytesLib.sol | 48/54 | **89%** |
| CastLib.sol | 23/27 | **85%** |
| MathLib.sol | 60/72 | **83%** |
| Auth.sol | 8/9 | **89%** |
| ERC20.sol | 49/77 | **64%** |
| PricingLib.sol | 45/88 | **51%** |

## Target Function Utilization (top 30)

| Target | Calls | Category |
|---|---|---|
| doomsday_brm_deposit_rounding | 806 | BRM edge-case |
| hub_notifyRedeem_forActor | 761 | Hub notification |
| poolEscrow_deposit | 661 | Escrow ops |
| doomsday_nav_no_negative_equity | 638 | NAV edge-case |
| queue_sync | 625 | Queue sync |
| liability_doomsday_isLiability_works | 610 | Liability |
| nav_closeGainLoss | 604 | NAV lifecycle |
| vault_mint | 598 | Vault claim |
| doomsday_brm_redeem_rounding | 596 | BRM edge-case |
| switch_pool | 594 | Pool switching |
| hub_notifyDeposit | 586 | Hub notification |
| hub_nav_closeGainLoss | 583 | NAV lifecycle |
| admin_createPool | 583 | Pool admin |
| vault_requestDeposit | 581 | Deposit flow |
| journal_balanced | 581 | Journal ops |
| asset_approveEscrow | 568 | Token ops |
| asset_mint | 562 | Token ops |
| switch_actor | 562 | Actor switching |
| admin_createPool_clamped | 561 | Pool admin |
| vault_redeem | 556 | Redeem flow |
| nav_initializeNetwork | 556 | NAV init |
| hub_nav_initializeHolding | 555 | Holding init |
| brm_forceCancelRedeemRequest | 553 | Cancel flow |
| shortcut_deposit_approve_issue | 541 | Deposit shortcut |
| brm_issueShares | 538 | Issue flow |
| hub_notifyRedeem | 535 | Hub notification |
| admin_unfreezeActor | 532 | Admin |
| journal_doomsday_unbalanced_reverts | 530 | Journal edge-case |
| admin_updateHoldingValue | 529 | Holding ops |
| hub_notifyDeposit_forActor | 525 | Hub notification |

## Property Verification (39 properties, ALL PASS)

### Cross-System Properties (P-CS)

| Property | Calls | Description |
|---|---|---|
| P-CS-1 | 462 | Hub-Spoke deposit consistency |
| P-CS-2 | 509 | Share issuance balance (with queuedShares delta) |
| P-CS-3a | 557 | Global escrow solvency |
| P-CS-4 | 594 | Price propagation (Hub price > 0 when Spoke set) |
| P-CS-5 | 538 | BRM epoch monotonicity |
| P-CS-6 | 428 | Share token conservation |
| P-CS-7 | 565 | Queue sync completeness |
| P-CS-8 | 506 | NAV accounting consistency |
| P-CS-9 | 610 | Accounting equation (asset + loss == equity + gain) |
| P-CS-10 | 472 | Cross-pool isolation |
| P-CS-11 | 535 | validUntil enforcement |

### Vault Properties (P-V)

| Property | Calls | Description |
|---|---|---|
| P-V-1 | 526 | View functions never revert |
| P-V-2 | 426 | Escrow solvency (PoolEscrow + globalEscrow >= sum(maxWithdraw)) |
| P-V-3 | 369 | maxDeposit honoured |
| P-V-4 | 932 | maxRedeem honoured |
| P-V-5 | 632 | Deposit increases totalShareSupply |
| P-V-6 | 631 | Redeem decreases supply |
| P-V-7 | 660 | Deposit rounding (protocol-favorable) |
| P-V-7b | 534 | Redeem rounding (protocol-favorable) |
| P-V-8 | 454 | Request callback delivery |

### Escrow Properties (P-E, P-PE)

| Property | Calls | Description |
|---|---|---|
| P-E-1 | 550 | Global escrow asset solvency |
| P-E-2 | 474 | Global escrow share solvency |
| P-PE-2 | 475 | PoolEscrow ERC20 balance >= total |
| P-PE-3 | 477 | PoolEscrow available balance consistency |

### Accounting Properties (P-ACC)

| Property | Calls | Description |
|---|---|---|
| P-ACC-1 | 529 | Holdings account consistency |
| P-ACC-2 | 474 | Debit/credit bounds |
| P-ACC-3 | 487 | Asset soundness |
| P-ACC-4 | 3 | Identity valuation |
| P-ACC-5 | 485 | Unauthorized hub ops fail |

### BRM E2E Properties

| Property | Calls | Description |
|---|---|---|
| P-BRM-E2E-1 | 533 | Pending deposit accounting |
| P-BRM-E2E-2 | 503 | Pending redeem accounting |
| P-BRM-E2E-3 | 507 | Epoch ordering |
| P-BRM-E2E-4 | 407 | Cancel reduces pending |

### NAV Properties

| Property | Calls | Description |
|---|---|---|
| P-NAV-1 | 507 | View liveness |
| P-NAV-2 | 375 | Non-negative |
| P-NAV-3 | 438 | Close zeros gain/loss |

### SyncManager Properties (P-SM)

| Property | Calls | Description |
|---|---|---|
| P-SM-1 | 183 | Price view liveness |
| P-SM-2 | 174 | Round-trip non-inflationary (assets <= input) |
| P-SM-3 | 207 | maxDeposit respects maxReserve |

## E2E vs Core-Only Coverage Comparison

### E2E が Core を大幅に上回るコントラクト

| Contract | Core | E2E | Delta | Reason |
|---|---|---|---|---|
| Accounting | 32% | **96%** | +64pp | Full journal/debit/credit lifecycle (E2E-exclusive) |
| BatchRequestManager | 0% | **85%** | +85pp | Hub-side epoch lifecycle (E2E-exclusive) |
| ShareClassManager | 0% | **78%** | +78pp | Share class management (E2E-exclusive) |
| Holdings | 0% | **76%** | +76pp | Holding initialization (E2E-exclusive) |
| Hub.sol | 0% | **73%** | +73pp | Pool/share management (E2E-exclusive) |
| NAVManager | 0% | **69%** | +69pp | NAV accounting (E2E-exclusive) |
| Gateway | 0% | **66%** | +66pp | Message routing (E2E-exclusive) |
| MultiAdapter | 0% | **65%** | +65pp | Adapter quorum (E2E-exclusive) |
| QueueManager | 0% | **66%** | +66pp | Queue sync (E2E-exclusive) |
| TransientArrayLib | 5% | **100%** | +95pp | Batch message processing |
| TransientBytesLib | 4% | **100%** | +96pp | Batch message encoding |

### Core が E2E を上回るコントラクト

| Contract | Core | E2E | Delta | Reason |
|---|---|---|---|---|
| Root.sol | 92% | 27% | -65pp | Admin/pause operations |
| PoolEscrow.sol | 100% | 52% | -48pp | Direct reserve/unreserve |
| AsyncVault.sol | 100% | 60% | -40pp | All vault entry points |
| PricingLib.sol | 85% | 51% | -34pp | More diverse price paths |
| AsyncRequestManager | 88% | 59% | -29pp | More claim path diversity |

## E2E-Exclusive Coverage（Core では不可能なパス）

1. **BRM epoch lifecycle**: requestDeposit → approveDeposits → issueShares → notifyDeposit（Hub内部の完全なエポック処理）
2. **Cross-chain message routing**: Gateway → MultiAdapter → MessageProcessor（実際のメッセージシリアライゼーション）
3. **Hub↔Spoke state reconciliation**: shares issuance on Spoke synced with Hub totalIssuance via queuedShares
4. **NAV accounting integration**: initializeHolding → updateHoldingValue → closeGainLoss → netAssetValue
5. **PoolEscrow.reserve via revokedShares**: BRM → Gateway → ARM.revokedShares → BalanceSheet.reserve（間接パス）
6. **Cancel flow across boundary**: ARM.cancelDeposit → Gateway → BRM.cancelDeposit → BRM.forceCancelDeposit
7. **SyncManager price propagation**: hub_notifySharePrice → SyncManager.convertToShares/Assets → round-trip verification

## Structurally Unreachable (E2E)

| Component | Lines | Reason |
|---|---|---|
| VaultRouter | 75 | Router経由でなく直接vault呼び出し（recon-coreでカバー） |
| SyncDepositVault | 11 | AsyncVaultのみデプロイ（SyncDepositVault未使用） |
| RefundEscrow | 4 | Refund claimパス未実装 |
| OpsGuardian/ProtocolGuardian | 53 | Admin guardian未配線 |
| AxelarAdapter/LayerZero/Wormhole | 118 | SimplifiedLocalAdapter使用（recon-aggregatorでカバー） |
| SimplePriceManager/MerkleProofManager | 103 | 未デプロイ |
| Spoke.crosschainTransferShares | - | centrifugeId mismatch in single-chain |

## Findings from E2E Fuzzing

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| F-1 | PoolEscrow.reserve() missing upper bound check | Info | Genuine — cross-system only |
| F-2 | totalAssets() uses stale price | Known | Design choice |
| F-5 | totalAssets() > PoolEscrow balance on price rise | Medium Candidate | Finding 2 の発展形 |
| F-6 | SyncManager round-trip precision loss | Low | Property修正で対応 |

---

## Post-Improvement Coverage Delta (TBD)

> 改善実装後に fuzzer を再実行し、以下を記録する:
> - 新規 target の到達率 (corpus hit count)
> - Property failure 変化 (新規 fail / 既存 fail 解消)
> - Overall coverage delta (lines / branches)
> - Optimization target の最大値
