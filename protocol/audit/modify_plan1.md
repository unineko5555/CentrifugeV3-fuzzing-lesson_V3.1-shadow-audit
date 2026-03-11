# Chimera Fuzzing Suite 改善計画 v2（精査後）

> 元の64件を1件ずつ精査し、本当に実装すべきもののみを残した。
> 削除理由は末尾の「削除項目一覧」セクションに記載。

---

## 残存項目: 10件

### 1. P-SM-2 tolerance 修正 (旧 1-12) — P1

- ファイル: `test/integration/recon-end-to-end/properties/SyncManagerProperties.sol` L35
- 修正: decimals差 (6 vs 18) による丸め誤差を考慮した tolerance に変更
- `lte(assets, testAmount)` → `lte(assets, testAmount + 1)` (1 wei tolerance)
- 理由: Finding 6 が明示的にこの精度問題を指摘。現状の strict 比較では false positive が発生し、プロパティが実質無効化されるリスク

### 2. oracle_stale_then_operate handler (旧 3-4) — P2

- 場所: `test/integration/recon-end-to-end/targets/` に新規ファイルまたは既存に追加
- 内容: `setPrice → warp(maxPriceAge + 1) → requestDeposit` を1つの target に連鎖
- 理由: stale oracle 下の操作は fuzzer のランダムシーケンスでは到達困難（warp 量と操作タイミングの組み合わせが必要）。意図的な multi-step target が有効

### 3. warp_to_member_expiry handler (旧 3-11) — P2

- 場所: `test/vaults/fuzzing/recon-core/targets/` に新規ファイルまたは既存に追加
- 内容: `warp(validUntil - block.timestamp + 1)` で membership expiry 境界を強制到達
- 理由: P-TH-2/7 (expired member transfer) の到達性が fuzzer の random warp では極めて低い。境界値への targeted warp が必要

### 4. poolEscrow_reserve_unclamped handler (旧 3-12) — P1

- 場所: `test/vaults/fuzzing/recon-core/targets/PoolEscrowTargets.sol` に追加
- 内容: clamp なしの `poolEscrow.reserve(amount)` 呼び出し（available を超える amount も許容）
- 理由: 既存の `poolEscrow_reserve` は `if (amount > available) amount = available` でクランプしており、Finding 1 (reserve() missing bound check) を隠蔽した実績がある。defense-in-depth として unclamped 版が必要

### 5. Price clamp 範囲拡大 (旧 5-2) — P2

- ファイル: `recon-hub/TargetFunctions.sol` L281
- 現状: `price = uint128(uint256(price) % 1000e18) + 1e15` (range: 0.001 ~ 1000)
- 修正: range を `[1, type(uint128).max / 2]` に拡大
- 理由: Finding 6 の精度問題は extreme price ratio で発現。現行レンジでは 18 decimals share vs 6 decimals asset の extreme case に到達不能

### 6. Echidna 辞書追加 (旧 8-3) — P2

- ファイル: 全 echidna.yaml
- 追加値:
  - `0x0`, `0x1`, `0x2`
  - `0xF4240` (1e6), `0xF423F` (1e6-1), `0xF4241` (1e6+1)
  - `0xDE0B6B3A7640000` (1e18)
  - `0x33B2E3C9FD0804000000000` (1e27)
  - `0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF` (uint128.max)
  - `0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE` (uint128.max - 1)
- 理由: ゼロコスト改善。decimals 境界値・overflow 境界値を辞書に含めることで fuzzer の探索効率が向上

### 7. optimize_precision_loss (旧 9-1) — P3

- 場所: `test/vaults/fuzzing/recon-core/targets/` に追加
- 内容: deposit → redeem round-trip の `|input - output|` を最大化する optimization target
- `function optimize_precision_loss(uint128 amount, uint128 price) public returns (int256)`
- 理由: Finding 6 の precision loss を体系的に最大化探索。Medusa optimization mode 専用

### 8. optimize_max_stuck_funds (旧 9-2) — P3

- 場所: `test/integration/recon-end-to-end/targets/` に追加
- 内容: `poolEscrow.total - sum(maxWithdraw)` を最大化（引き出し不能な閉じ込め額の探索）
- `function optimize_max_stuck_funds() public returns (int256)`
- 理由: Finding 5 (totalAssets > PoolEscrow) の根本原因である stuck funds を体系的に探索

### 9. audit_memo.md 更新 (旧 10-1) — P3

- ファイル: `protocol/audit/audit_memo.md`
- 内容: 上記改善の実施記録を追加

### 10. coverage レポート更新 (旧 10-2) — P3

- ファイル: `protocol/audit/e2e_coverage.md`, `protocol/audit/aggregator_coverage.md`
- 内容: 改善実装後の coverage delta を記録

---

## 削除項目一覧（54件）と削除理由

### 旧 1-1. P-BRM-5/6 方向修正 → **削除**
**理由**: 再分析の結果、`gte(totalUserPending, pendingDeposit)` は正しい。approve 後は aggregate pending が減少するが per-user pending は claim まで残存するため、`sum(user) >= aggregate` が正しい不変条件。`eq` に変更すると approve 後に false positive が発生する。

### 旧 1-2. P-CS-1 epoch==0 条件緩和 → **削除**
**理由**: `if (dEp > 0 || iEp > 0) continue` は必要な条件。epoch > 0 (approve 済み) の pending tracking は Hub suite の P-BRM-5 が別途カバーしている。E2E の P-CS-1 は epoch==0（未 approve）の cross-system 整合性に特化しており、条件除去は false positive を生む。

### 旧 1-3. P-ORACLE-1 削除 → **削除**
**理由**: IdentityValuation での trivially true は「害がない」だけで「危険ではない」。OracleValuation は別 shortcut (`shortcut_create_oracle_pool_and_holding`) で既にテスト対象。新プロパティ追加の ROI が低い。

### 旧 1-4. P-ACC-1 削除 → **削除**
**理由**: Solidity 0.8 の panic で自動検出されるとはいえ、明示的プロパティを削除するメリットがない。現状で実害なし。

### 旧 1-5. DISABLED property_totalAssets_solvency 代替 → **削除**
**理由**: E2E の P-V-2 (`sum(maxWithdraw) <= escrow balance`) が同等の solvency チェックをカバー。P-CS-3 Part A も有効。core suite 単体での重複実装は不要。

### 旧 1-6. DISABLED property_escrow_conservation 代替 → **削除**
**理由**: E2E の P-E-1/P-E-2 (`escrow asset/share solvency`) + P-PE-2 (`ERC20 balance >= total`) が globalEscrow + poolEscrow の solvency をカバー。core 単体での再実装は冗長。

### 旧 1-7. DISABLED property_VR_1 canary 版 → **削除**
**理由**: VaultRegistry のリンク検証は E2E の P-V-1 (views never revert) で間接的にカバー。canary 実装の ROI が低い。

### 旧 1-8. P-CS-3b 再有効化 → **削除**
**理由**: Finding 1 が未修正の状態で有効化すると常時 fail。修正後の有効化はコードレビュー時の TODO であり、fuzzing 改善計画の scope 外。

### 旧 1-9. Medusa panic config 変更 → **削除**
**理由**: Centrifuge のコードは `unchecked` block を意図的に使用しており、panic 検出を有効化すると false positive が大量発生する。arithmetic overflow/underflow は Solidity 0.8 デフォルトで検出される。

### 旧 1-10. P-PE-3 skip 除去 → **削除**
**理由**: 1-8 と同理由。Finding 1 未修正状態では skip が必要。修正後の除去はコードレビュー TODO。

### 旧 1-11. P-CS-4 確認のみ → **削除**
**理由**: 元から「追加修正不要」と記載。確認は完了済み。

### 旧 2-1. P-NEW-BRM-EPOCH-STUCK → **削除**
**理由**: epoch が進行しないのはファザーがまだ approve/issue を呼んでいないだけ。canary として実装してもノイズが多く、genuine bug の検出に寄与しない。

### 旧 2-2. P-NEW-PHANTOM-SHARES → **削除**
**理由**: P-CS-2 (`spoke supply + queued == hub issuance + queued`) + P-CS-6 (`totalSupply >= sum(balances)`) で phantom shares は既に検出可能。

### 旧 2-3. P-NEW-DOUBLE-CLAIM → **削除**
**理由**: ERC-7540 プロパティ asyncVault_6 (`claim > max reverts`) + asyncVault_9 (`max > 0 → method(max) succeeds`) で double claim は既にカバー。

### 旧 2-4. P-NEW-ESCROW-BALANCE-CONSERVATION → **削除**
**理由**: P-PE-2 + P-E-1 + P-E-2 の組み合わせで conservation は検証済み。新規 ghost を大量追加する割に検出力の向上が限定的。

### 旧 2-5. P-NEW-REENTRANCY-GUARD → **削除**
**理由**: Centrifuge は ERC-20 の standard transfer のみ使用し callback hook がない。receive() reentrancy は native ETH 受取時のみだが、プロトコルは ERC-20 ベース。ReentrantActor は不要。

### 旧 2-6. P-NEW-FRONTRUNNING-PRICE → **削除**
**理由**: approval → issue 間の price 変動は Hub の正常な動作。canary にしても false positive が大量発生し、actionable な結果にならない。

### 旧 2-7. P-NEW-ZERO-AMOUNT-OPERATIONS → **削除**
**理由**: 既存の clamped target が amount > 0 を保証しており、zero amount パスは到達しない。明示的な zero-amount target を追加するなら handler 側の変更が必要だが ROI が低い。

### 旧 2-8. P-NEW-CROSS-POOL-ISOLATION-STRONG → **削除**
**理由**: P-CS-10 が既に全 inactive pool の holdings を before/after 比較している。accountValues 追加は P-CS-8/P-CS-9 でカバー済み。

### 旧 2-9. P-NEW-OVERFLOW-SAFE-MATH → **削除**
**理由**: 元から「明示的プロパティは不要」と記載。Solidity 0.8 のデフォルト overflow check で十分。

### 旧 2-10. P-NEW-TRANSIENT-STORAGE-LEAK → **削除**
**理由**: Centrifuge の accounting.debited()/credited() は transient storage ではなく通常の batching state。P-BRM-1 (`debited == credited in batch`) で既にカバー。

### 旧 3-1. HubHandlerCallbackTargets → **削除**
**理由**: HubHandlerTargets.sol が既に存在し、hubHandler_updateHoldingAmount/updateShares/request/registerAsset の target を含む。coverage 26.5% はターゲット不足ではなく、state prerequisite（pool/holding/shareClass の事前作成が必要）が原因。shortcut で state を準備すれば coverage は自然に向上する。

### 旧 3-2. ReentrantActor.sol → **削除**
**理由**: 2-5 と同理由。ERC-20 ベースのプロトコルに callback reentrancy は適用されない。

### 旧 3-3. partial_approval handler → **削除**
**理由**: 既存の `brm_approveDeposits` が `maxApproval` パラメータを fuzzer のランダム値で呼んでおり、`maxApproval < pendingDeposit` のケースは自然に探索される。明示的 handler は冗長。

### 旧 3-5. donate_to_escrow handler → **削除**
**理由**: Centrifuge の totalAssets は share price ベースで計算され、ERC20.balanceOf() に依存しない。donation attack は price oracle を経由しない限り accounting に影響しない。

### 旧 3-6. unauthorized_hub_call handler → **削除**
**理由**: P-ACC-5 が既に `vm.prank(0xDEAD)` で unauthorized call を検証。全 auth 関数の網羅は unit test の責務であり、fuzzing の scope 外。

### 旧 3-7. cancel_after_fulfill handler → **削除**
**理由**: 既存の fuzzer のランダムシーケンスが `notifyDeposit → cancelDeposit` の順序を自然に探索する。明示的 handler は冗長。

### 旧 3-8. epoch_skip handler → **削除**
**理由**: 既存の shortcut (`shortcut_approve_and_issue_shares`) がランダム反復で epoch cycling を実現。明示的 N 回ループは fuzzer の探索多様性を減少させる。

### 旧 3-9. first_deposit_single_wei handler → **削除**
**理由**: Centrifuge の async deposit モデルでは deposit → approve → issue の3段階を経るため、first-depositor inflation attack (ERC-4626 classic) は構造的に適用されない。share price は approve 時に管理者が設定する。

### 旧 3-10. multi_pool_switch_and_operate handler → **削除**
**理由**: E2E の既存 handler が `activePoolId` を entropy でスイッチしている。明示的 compound target は fuzzer の sequence coverage を狭める。

### 旧 4-1. Actor pool 拡張 → **削除**
**理由**: 6 actor に拡張すると fuzzer の budget の ~20% が auth revert パスに浪費される。2 actor + `vm.prank(0xDEAD)` (P-ACC-5) で auth 境界は十分検証可能。unauthorized actor は既存プロパティで検証済み。

### 旧 4-2. 0x40000 非 ward → **削除**
**理由**: 4-1 の削除に伴い不要。

### 旧 4-3. 0x50000 frozen member → **削除**
**理由**: 4-1 の削除に伴い不要。P-TH-1 (frozen bypass) は既存の handler で `freeze()` → `transfer()` の順序で検証可能。

### 旧 4-4. ReentrantActor deploy → **削除**
**理由**: 3-2/2-5 の削除に伴い不要。

### 旧 4-5. Medusa senderAddresses 拡張 → **削除**
**理由**: 4-1 の削除に伴い不要。

### 旧 4-6. Echidna sender 設定 → **削除**
**理由**: 4-1 の削除に伴い不要。

### 旧 4-7. 初期 multi-pool デプロイ → **削除**
**理由**: E2E の shortcut が pool 作成を含んでおり、fuzzer のシーケンス初期で複数 pool が作成される。setup での固定 2 pool は fuzzer の探索順序を制約し、初期化パスのカバレッジを減少させる。

### 旧 5-1. Pool 作成の段階的分離 → **削除**
**理由**: 不完全状態での操作は revert するだけで、vulnerability ではない。fuzzer が revert を踏んでも state は変化しないため、coverage 向上に寄与しない。

### 旧 5-3. NAV→Price 伝播 shortcut → **削除**
**理由**: 6段階の連鎖 shortcut は fuzzer の sequence diversity を大幅に減少させる。各段階は既存 target として個別に呼び出し可能であり、fuzzer のランダム組み合わせのほうが edge case を発見しやすい。

### 旧 5-4. Multi-actor deposit/redeem shortcut → **削除**
**理由**: 既存の shortcut (`shortcut_deposit`, `shortcut_redeem`) が actor 切り替えと組み合わさることで同等のシーケンスが生成される。compound shortcut は探索空間を狭める。

### 旧 6-1. ghostTotalAssetInSystem → **削除**
**理由**: 2-4 (ESCROW-BALANCE-CONSERVATION) の削除に伴い不要。

### 旧 6-2. ghostSharesMintedToUser → **削除**
**理由**: 2-2 (PHANTOM-SHARES) の削除に伴い不要。

### 旧 6-3. ghostLastEpochAdvanceTimestamp → **削除**
**理由**: 2-1 (BRM-EPOCH-STUCK) の削除に伴い不要。

### 旧 6-4. ghostPriceAtApproval/Issue → **削除**
**理由**: 2-6 (FRONTRUNNING-PRICE) の削除に伴い不要。

### 旧 6-5. BeforeAfter 全 pool capture 確認 → **削除**
**理由**: 元から「修正不要（既に全 pool capture 済み）」と記載。

### 旧 7-1. FeeOnTransferMockERC20 → **削除**
**理由**: Centrifuge は自前の ERC-20 (ShareToken) と標準的な stablecoin (USDC 等) を想定。fee-on-transfer トークンは scope 外（プロトコルドキュメントで非対応と明記される可能性が高い）。

### 旧 7-2. ReentrantActor.sol → **削除**
**理由**: 3-2 と重複。かつ 2-5 の理由で不要。

### 旧 7-3. DelayedDeliveryAdapter → **削除**
**理由**: メッセージ遅延・順序逆転のシミュレーションは実装コストが非常に高く、MockGateway の即時配信で十分な coverage を達成している。cross-chain メッセージングの fault はプロトコルレベルのリスクであり、fuzzing の scope を超える。

### 旧 7-4. StaleOracleValuation → **削除**
**理由**: 項目 2 (oracle_stale_then_operate handler) が同等の stale oracle テストを time warp で実現する。専用 mock の追加は不要。

### 旧 8-1. blockTimestampDelayMax 拡大 → **削除**
**理由**: 1 year への拡大は fuzzer が大半の時間を「遠い未来」で過ごすことになり、正常動作パスの coverage が低下する。1 week で十分な membership expiry テストが可能（項目 3 の targeted warp で補完）。

### 旧 8-2. Medusa panic config → **削除**
**理由**: 1-9 と重複。かつ 1-9 の理由で削除。

### 旧 8-4. Phase 分離 config → **削除**
**理由**: Phase 分離はプロセス・運用の決定であり、コード改善計画の scope 外。必要時に随時作成すればよい。

### 旧 8-5. Phase2 filterFunctions → **削除**
**理由**: 8-4 の削除に伴い不要。

### 旧 9-3. optimize_max_price_divergence → **削除**
**理由**: Hub-Spoke 間の price divergence は MockGateway の即時配信では発生しない。DelayedDeliveryAdapter (7-3) を削除した以上、divergence 最大化 target は到達不能。

---

## 総計: 10件（64件中54件を削除）

| カテゴリ | 残存件数 |
|---------|----------|
| プロパティ修正 | 1 |
| 新規 Handler/Target | 3 |
| Shortcut 修正 | 1 |
| Fuzzer 設定 | 1 |
| Optimization target | 2 |
| ドキュメント更新 | 2 |

---

## 実装優先度

### P1（高優先 — genuine finding の再発防止・精度改善）
- **1.** P-SM-2 tolerance 修正（Finding 6 対応）
- **4.** poolEscrow_reserve_unclamped（Finding 1 隠蔽回避）

### P2（中優先 — 探索品質向上）
- **2.** oracle_stale_then_operate handler
- **3.** warp_to_member_expiry handler
- **5.** Price clamp 範囲拡大
- **6.** Echidna 辞書追加

### P3（低優先 — 長期改善）
- **7.** optimize_precision_loss
- **8.** optimize_max_stuck_funds
- **9.** audit_memo.md 更新
- **10.** coverage レポート更新
