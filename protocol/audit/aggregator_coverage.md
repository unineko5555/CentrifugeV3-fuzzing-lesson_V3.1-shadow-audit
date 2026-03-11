# Aggregator Medusa Coverage Report

**Corpus**: 85 sequences / 5,839 calls | **Failures**: 0/8 properties | **Unique methods**: 52

## Scope

Aggregator スイートは **Gateway + MultiAdapter + GasService** のメッセージングレイヤーに特化。
Hub/Spoke/Vault 系コントラクトはデプロイせず、MockProcessor + MockAdapter で境界を模擬。

## Per-Contract Coverage (in-scope messaging)

| Contract | Hit/Total | Coverage | Notes |
|---|---|---|---|
| MultiAdapter.sol | 74/86 | **86%** | Quorum voting, adapter管理, session管理 |
| Gateway.sol | 100/128 | **78%** | Send/handle, batch, fail/retry, block/unblock |
| GasService.sol | 41/92 | **45%** | Prepay, repay, unpaid mode |
| MessageLib.sol | 43/270 | **16%** | Serialize/deserialize (E2Eの方が網羅的) |

### Supporting Libraries

| Library | Hit/Total | Coverage |
|---|---|---|
| TransientArrayLib.sol | 19/19 | **100%** |
| TransientBytesLib.sol | 25/28 | **89%** |
| BytesLib.sol | 33/54 | **61%** |
| Auth.sol | 5/9 | **56%** |
| MathLib.sol | 26/72 | **36%** |

## Target Function Utilization

| Target | Calls | Category |
|---|---|---|
| gateway_setUnpaidMode | 285 | GasService integration |
| gateway_failAndRetry | 277 | Failed message lifecycle |
| gateway_repay | 228 | Gas repayment |
| adapter_deliverWithStaleSession | 218 | Session stale delivery |
| gateway_handleDirect | 218 | Direct message handling |
| gateway_withBatchNoLock | 213 | Batch without lock callback |
| admin_reconfigureTwoAdapters | 211 | Adapter reconfiguration |
| adapter_deliverDuplicate | 210 | Duplicate vote delivery |
| admin_reconfigureAdapters | 209 | Adapter reconfiguration |
| gateway_withBatch | 203 | Batch with lock callback |
| admin_unpause | 202 | Pause/unpause lifecycle |
| adapter_deliver | 200 | Normal quorum delivery |
| admin_reconfigureSingleAdapter | 195 | Single adapter reconfig |
| gateway_send | 190 | Outgoing message send |
| admin_pause | 181 | Pause lifecycle |
| adapter_deliverBelowThreshold | 179 | Sub-threshold delivery |
| gateway_blockOutgoing | 175 | Pool blocking |
| gateway_retry | 161 | Message retry |
| adapter_deliverFromMultiple | 160 | Multi-adapter delivery |
| gateway_createFailedMessage | 155 | Failed message creation |
| admin_setPoolAdapters | 146 | Pool-specific adapter config |

## Property Verification (8 properties, ALL PASS)

| Property | Calls | Description |
|---|---|---|
| P-AGG-1 | 249 | No delivery without quorum (threshold=2) |
| P-AGG-2 | 238 | Session reset clears votes |
| P-AGG-3 | 177 | No double-vote bypass |
| P-AGG-4 | 184 | Failed message accounting (failed >= retried) |
| P-AGG-5 | 179 | Unpaid mode accounting (underpaid >= repaid) |
| P-AGG-6 | 175 | Outgoing blocked enforcement |
| P-AGG-7 | 199 | Batch integrity (withBatch + lockCallback) |
| P-AGG-8 | 178 | Pause blocks operations |

## Meaningful Path Coverage Analysis

### 十分にカバーされているフロー

1. **Quorum Voting**: adapter_deliver (200) + adapter_deliverFromMultiple (160) + adapter_deliverDuplicate (210) — 3/3アダプター構成で2/3 thresholdの全パターン行使
2. **Session Management**: adapter_deliverWithStaleSession (218) — session変更後の古いvote無効化を検証
3. **Failed Message Lifecycle**: gateway_createFailedMessage (155) → gateway_failAndRetry (277) → gateway_retry (161) — 失敗メッセージの作成→再試行→成功の完全サイクル
4. **Batch Processing**: gateway_withBatch (203) + gateway_withBatchNoLock (213) — lockCallback有無の両パターン
5. **Gas Management**: gateway_setUnpaidMode (285) → gateway_repay (228) — underpaidメッセージの作成と返済
6. **Adapter Reconfiguration**: admin_reconfigureAdapters (209) + admin_reconfigureTwoAdapters (211) + admin_reconfigureSingleAdapter (195) — 動的adapter構成変更
7. **Pause/Block**: admin_pause (181) + admin_unpause (202) + gateway_blockOutgoing (175) — 運用制御

### カバレッジが低い領域

| 領域 | Coverage | 理由 | 補完状況 |
|------|----------|------|---------|
| MessageLib.sol | 16% | Aggregator は serialize/deserialize の一部のみ使用。完全なメッセージ種別は E2E スイートで網羅 | E2E: 66% |
| GasService.sol | 45% | estimateGas/payGas 等の外部adapter連携パスが未到達 | 実adapter未使用のため構造的に不可 |
| MessageDispatcher.sol | 0% | Aggregator スイートではデプロイ対象外 | E2E: 48% |
| MessageProcessor.sol | 0% | MockProcessor で代替 | E2E: 66% |

### Aggregator-Exclusive Coverage (他スイートでは不可能なパス)

1. **Quorum threshold enforcement**: 3アダプター構成で2/3 threshold — E2E はSimplifiedLocalAdapter(threshold=1)のため検証不可
2. **Session invalidation**: adapter reconfig → session変更 → 旧session vote無効化
3. **Double-vote prevention**: 同一アダプターからの重複delivery検出
4. **Failed message retry**: 明示的なfailAndRetry + createFailedMessage パス
5. **Batch with lockCallback**: Gateway.withBatch → callback → send の原子的バッチ処理
6. **Pool-level blocking**: blockOutgoing → send失敗の確認 → unblock

## Structurally Unreachable

| Component | Reason |
|---|---|
| AxelarAdapter / LayerZero / Wormhole | 実adapter未使用 (MockAdapter) |
| RecoveryAdapter | Recovery flow 未実装 |
| MessageDispatcher / MessageProcessor | MockProcessor で代替 |
| Hub / Spoke / Vault 全般 | Aggregator スコープ外 |
| GasService.estimateGas (外部adapter連携) | 実adapter不在 |

## E2E との相補性

| メトリック | Aggregator | E2E | Combined |
|---|---|---|---|
| Gateway.sol | 78% | 66% | ~85% (相互補完) |
| MultiAdapter.sol | 86% | 65% | ~90% |
| GasService.sol | 45% | 65% | ~70% |
| MessageLib.sol | 16% | 66% | ~68% |

Aggregator スイートは **quorum voting / session管理 / failed message** の深い検証を提供し、E2E スイートの **end-to-end メッセージフロー** と相補的。両スイート合算でメッセージングレイヤーの ~85% をカバー。

---

## Post-Improvement Coverage Delta (TBD)

> 改善実装後 (2026-03-10) に fuzzer を再実行し、Echidna dictionary 追加による coverage delta を記録する。
