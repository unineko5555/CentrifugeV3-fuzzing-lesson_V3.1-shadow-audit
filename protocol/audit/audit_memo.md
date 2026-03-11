# Centrifuge Protocol v3.1 - Audit Memo

## Phase 3 (recon-e2e) E2E Fuzzing Findings

### Finding 1: PoolEscrow.reserve() バウンドチェック欠如 — core,e2e

根本原因: PoolEscrow.reserve() に require(reserved <= total) がない。一方 withdraw() にはこのチェックがある — 非対称なバグ。

攻撃パス:

1. price=1.0 で 100 USDC を deposit → total = 100
2. price が 1.5 に上昇
3. redeem → Hub が PricingLib.shareToAssetAmount() で payoutAssetAmount = 150 を計算
4. revokedShares() → balanceSheet.reserve(150) → reserved = 150 > total = 100
5. availableBalanceOf() が 0 にアンダーフロー、withdraw() が revert → 資金が永久にロック

深刻度: High — 影響を受けた PoolEscrow の全ユーザーの資金が永久ロック

緩和策: PoolEscrow.reserve() に require(reserved <= total) を追加（withdraw() の既存チェックと対称にする）

#### PR #740 の分析 — "修正" の実態

**修正 PR**: [#740](https://github.com/centrifuge/protocol/pull/740) "Add explicit error for reserve underflow in pool escrow"

- commit: [`5cd5bf8`](https://github.com/centrifuge/protocol/commit/5cd5bf8538ea91f6a6b9a094baa01ec86d1841ff)
- 著者: Jeroen / hieronx (Centrifuge コア開発者)
- マージ: 2025-10-15
- v3.1.0 リリースノート Fixes 欄に "PoolEscrow reserve underflow" として記載

**修正内容** — `withdraw()` に explicit revert を追加（`reserve()` は未変更）:

```diff
 function withdraw(...) external auth {
     Holding storage holding_ = holding[scId][asset][tokenId];
+    require(holding_.total >= holding_.reserved, InsufficientBalance(asset, tokenId, value, 0));
     uint128 balance = holding_.total - holding_.reserved;
```

**この commit が意味すること**:

- `reserved > total` 自体を禁止する修正**ではない**
- `withdraw()` の arithmetic underflow panic を explicit revert に変えただけ
- `reserve()` は未変更 → over-reserve は依然として許容
- IBalanceSheet.sol L162 "It is possible to reserve more than the current balance" も維持
- unit test (PoolEscrow.t.sol) も over-reserve を正常動作として検証

**結論**: チームは `reserved > total` を **intended design** として維持。
問題視したのは over-reserve 自体ではなく、その状態で `withdraw()` が generic panic になること。
"security bug fix" ではなく **"explicit revert hygiene"** と読むのが正確。

#### M01 の最終評価

| 論点                                   | 判定                                                   |
| -------------------------------------- | ------------------------------------------------------ |
| `reserved > total` 自体                | intended design (IBalanceSheet doc + unit test が証明) |
| `withdraw()` の arithmetic panic       | undesired → PR #740 で explicit revert に改善          |
| M01 "missing bound check in reserve()" | チームが意図的に入れていない → **invalid**             |

- **v3.1_latest (Cantina)**: 提出根拠なし。修正済み + 意図的設計
- **v3.1 (Sherlock contest)**: "over-reserve 時の withdraw panic" = robustness / revert hygiene。severity は Low 以下
- Sherlock judge の Invalid 判定: 推論過程は雑 ("auth = safe") だが **結論は正しかった**

### Finding 2: totalAssets() Uses Stale Price [INFORMATIONAL / KNOWN]

**Status: Known Design Choice - Do NOT submit to Sherlock**

BaseVaults.totalAssets() uses cached epoch prices via spoke.pricesPoolPer(..., false).
Between epochs, reported value can diverge from actual backing.

Known issue analysis:

- README.md L80: DIRECTLY related (stale pricePoolPerAsset acknowledged)
- BaseVaults.sol NatSpec L173-174: explicit warning
- recon-core Properties.sol L234: tolerance-based solvency property
- BaseVaults.sol L196-197: priceLastUpdated() API provided

Conclusion: Team fully aware. Inherent ERC-4626/7540 async design trade-off.

### Finding 3: AsyncRequestManager.revokedShares() No Bound Validation

**Status: Same root cause as Finding 1 - Merge for submission**

Same call chain upstream. Fix in Finding 1 resolves both.|

## Phase 4 (recon-core) Vault Fuzzing Findings

### Finding 4: ARM.max\* View Functions Don't Check Vault Linkage [Low / Known]

**Status: Known Issue — Do NOT submit to Sherlock**

`AsyncRequestManager.maxDeposit()` / `maxMint()` / `maxWithdraw()` / `maxRedeem()` は
`_checkIsLinked()` を呼ばないが、対応する state-changing 関数（`deposit`, `mint`, `withdraw`, `redeem`）
は全て `_checkIsLinked()` を呼び、unlinked vault では `VaultNotLinked()` で revert する。

**コードパス:**

```
// View (linkage チェックなし):
AsyncVault.maxDeposit(controller)
  → ARM.maxDeposit(vault, user)         // L537: NO _checkIsLinked
    → _maxDeposit(vault, user)           // returns stored claimable amount

// Mutative (linkage チェックあり):
AsyncVault.deposit(assets, receiver, controller)
  → ARM.deposit(vault, assets, receiver, controller)  // L374-388
    → _checkIsLinked(vault)              // L379: REVERTS if not linked
```

**ERC-4626仕様違反:**

> maxDeposit: "MUST return the maximum amount that could be transferred and not cause a revert"
> "if deposits are entirely disabled (even temporarily) it MUST return 0"

unlinked vault では deposit() が revert するのに maxDeposit() が非ゼロを返す → ERC-4626違反。

**unlinkVault のアクセス経路:**

```
Hub (cross-chain governance)
  → Gateway message (VaultUpdateKind.Unlink)
    → VaultRegistry.updateVault() [auth modifier]
      → unlinkVault()  // sets isLinked = false
```

**Sherlock 提出不可の根拠:**

1. **既知の問題に該当** — README.md L85:

   > "Liquidity can be stuck if all vaults are unlinked"
   > VR-1 のインパクト（unlinked vault → claim 不可 → 流動性ロック）はこの既知の問題のサブセット。

2. **コンテストルール** — README.md L40:

   > "Issues related to EIP non-compliance can be valid only if they lead to Medium or High impact, besides the EIP violation itself."
   > ERC 違反単体では不十分。ERC 違反を超える Medium/High インパクトが必要。

3. **追加インパクトが Low 止まり:**
   - view 関数の不整合 → integrator 側の tx 失敗、gas 浪費
   - admin（governance）が linkVault() で即座に復旧可能
   - 永久的な資金ロスなし

---

## Phase 5 (Wave 5 E2E) Findings

### Finding 5: totalAssets() > PoolEscrow Balance → Withdraw/Redeem Revert [Medium Candidate]

**Status: 要検証 — Finding 2の発展形**

**問題**: `totalAssets() = convertToAssets(totalSupply())` は価格×供給量の理論値。
一方 `withdraw/redeem` は PoolEscrow から出金する。価格上昇時に `totalAssets() > PoolEscrow.balance` となり、
`totalAssets()` 分の引き出しを期待する外部プロトコルが revert に遭遇する。

**資金フロー**:

```
requestDeposit: user → globalEscrow (ERC20転送)
fulfillDeposit: globalEscrow → PoolEscrow (authTransferTo)
withdraw/redeem: PoolEscrow → user (PoolEscrow.withdraw → authTransferTo)
```

**根本原因**: `totalAssets()` は pricePoolPerShare ベースの推定値であり、PoolEscrow の実残高と連動しない。
share価格が上昇すると理論値が実残高を超え、ERC-4626 の「totalAssets は引き出し可能額の上限」という暗黙の前提に違反。

**Medusa再現**: 8シーケンスで検出。`admin_updateSharePrice(大値)` → `hub_notifySharePrice` → `property_V_2_totalAssets_solvency` で
`globalEscrow.balance < totalAssets` が成立。

**評価**:

- Finding 2 (stale price) の延長だが、ここでは stale ではなく「正しく伝播された高価格」が原因
- `maxWithdraw` でガードされるため直接的な資金ロスはない
- 外部プロトコル連携で `totalAssets()` を信頼すると判断を誤る

### Finding 6: SyncManager convertToShares/Assets Round-Trip Precision Loss [Low / Property修正]

**Status: プロパティ修正が必要 — decimals差が原因**

asset decimals (6) ≠ share decimals (18) のとき、PricingLib.convertWithPrices の丸めで
`assets → shares → assets` ラウンドトリップが 1 wei 以上の誤差を生む。
P-SM-2 の tolerance `<= 1 wei` が厳しすぎる。decimals差を考慮した許容誤差に修正要。

---

## Test Results

### Phase 3 (recon-e2e)

- Foundry: 15/15 pass
- Echidna: 148/150 (2 = Finding 1: P-PE-1, P-PE-3)
- Medusa: 127/128 (1 = Finding 2: totalAssets solvency)

### Phase 4 (recon-core) — Round 3 after fixes

- Foundry: 56/56 pass (16 core + 17 e2e + others)
- Medusa: totalAssets_solvency のみ (既知 = Finding 2)

### Phase 5 (Wave 5 E2E) — SyncManager + Hub通知追加後

- Foundry: 68/68 pass (4 suites)
- Medusa: 3 fail (P-CS-4: 8seq, P-V-2: 8seq, P-SM-2: 3seq)
  - P-CS-4: 非同期価格伝播の設計動作 → tolerance追加で修正要
  - P-V-2: Finding 5 (totalAssets > escrow balance)
  - P-SM-2: Finding 6 (decimals差による丸め誤差)
- Coverage: 55.5% (2610/4700 lines), SyncManager 4.4%→61.4%

---

## Fuzzing Suite Improvements (2026-03-10)

精査後の改善計画(64件→10件)を実装。詳細は `modify_plan1.md` を参照。

### Implemented Changes

1. **P-SM-2 拡張**: テスト金額を3パターン(1wei, 1e6, 1e18)に拡張 — Finding 6 boundary coverage
2. **PriceAgeTargets**: `priceAge_stale_then_requestDeposit` multi-step handler追加 — stale oracle探索
3. **TimeWarpTargets**: `time_warp_to_member_expiry` targeted boundary handler追加 — P-TH-2/7到達性改善
4. **PoolEscrowTargets**: `poolEscrow_reserve_unclamped` handler追加 — Finding 1 defense-in-depth
5. **Price clamp**: Hub `oracleValuation_setPrice_clamped` range を [0.0001, 1_000_000] D18 に修正 (Finding 7 で uint128.max/2 が P-ACC-1 false positive を引き起こしたため)
6. **Echidna dictionary**: decimals/overflow境界値を全4 config に追加
7. **DoomsdayTargets (core)**: `optimize_precision_loss` optimization target追加
8. **DoomsdayTargets (E2E)**: `optimize_max_stuck_funds` optimization target追加
