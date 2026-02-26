# Echidna / Medusa E2E Fail Analysis

> recon-e2e スイートの Echidna・Medusa 実行で検出された failure の記録と分析。

## 実行環境

- **スイート**: `test/integration/recon-end-to-end/` (30 .sol + 2 configs)
- **Echidna**: `--test-limit 2000`, assertion mode, `echidna_e2e.yaml`
- **Medusa**: `testLimit: 2000`, assertion mode, `medusa_e2e.json`
- **Foundry**: `forge test --match-contract CryticToFoundry` — 15/15 pass

---

## Echidna Results: 148/150 pass, 2 fail

### Fail 1: `property_PE_1_total_gte_reserved`

```
property_PE_1_total_gte_reserved(): failed!
  Call sequence:
    brm_requestRedeem(...)
    hub_approveRedeems(...)
    hub_revokeShares(...)
    hub_revokeShares(...)   ← 2回目の revokeShares で reserved > total
```

- **プロパティ**: `PoolEscrow.holding.total >= PoolEscrow.holding.reserved`
- **根本原因**: `PoolEscrow.reserve()` (L46-51) に `reserved + value <= total` の上限チェックなし
- **コールチェーン**: `Hub.revokeShares()` → message → `AsyncRequestManager.revokedShares()` → `BalanceSheet.reserve()` → `PoolEscrow.reserve()`

### Fail 2: `property_CS_3_escrow_solvency`

```
property_CS_3_escrow_solvency(): failed!
  Call sequence: (Fail 1 と同一シーケンス)
```

- **プロパティ**: Part B = `PoolEscrow.holding.total >= PoolEscrow.holding.reserved`
- **根本原因**: Fail 1 と同一（`reserve()` の bounds check 欠如）
- **意味**: Hub↔Spoke 全体のソルベンシーチェーンで同じ違反を検出

---

## Medusa Results: 127/128 pass, 1 fail

### Fail 1: `property_totalAssets_solvency` (assertion failure)

```
[FAILED] Assertion Test: CryticTester.property_totalAssets_solvency()
  totalAssets > actualAssets
```

- **プロパティ**: `vault.totalAssets() <= ERC20(asset).balanceOf(address(escrow))`
- **根本原因**: `BaseVaults.totalAssets()` (L168-170) が `convertToAssets(totalSupply)` でキャッシュされた Spoke 価格を使用。NAV 変更後に価格が Spoke に propagate されていない状態で `totalAssets` が実 escrow 残高を上回る。
- **コールチェーン**: `totalAssets()` → `convertToAssets()` → `spoke.pricesPoolPer(..., false)` ← false = キャッシュ価格

---

## 既知問題・デザイン選択分析

### 調査したソース

| ソース | 確認結果 |
|--------|---------|
| `README.md` L65-93 (Sherlock known issues) | F1: 未記載, F2: L76/L80 に該当 |
| Recon 2025-04 (v3 audit) | PoolEscrow.reserve 指摘なし |
| Cantina 2025-05 (v3) | PoolEscrow 指摘なし |
| Cantina 2025-08 (v3) | BalanceSheet スコープだが指摘なし |
| BurraSec 2025-10 (v3.1) | PoolEscrow スコープ外 |
| Electisec 2025-10 (v3.1) | PoolEscrow スコープ外 |
| `test/core/unit/PoolEscrow.t.sol` | **reserved > total を意図的にテスト** |
| `test/vaults/fuzzing/recon-core/` | P-PE-1 プロパティあり、ターゲットでクランプ |

### F1: PoolEscrow.reserve() bounds — Design Choice

**判定: 意図的なデザイン選択**

決定的証拠:

1. **PoolEscrow.t.sol L68**: `total=0` の状態で `reserve(100)` を呼び、`availableBalanceOf` が 0 を返すことを正常動作として検証

```solidity
// test/core/unit/PoolEscrow.t.sol:66-70
escrow.reserve(scId, asset, tokenId, 100);
assertEq(escrow.availableBalanceOf(scId, asset, tokenId), 0, "Still zero, nothing is in holdings");
// → reserved(100) > total(0) を意図的に作成
```

2. **PoolEscrow.t.sol L118-128**: `deposit(1000)` → `reserve(500)` → `reserve(600)` で `reserved=1100 > total=1000` を明示的にテスト。withdraw がブロックされ、unreserve で回復することを検証。

```solidity
// test/core/unit/PoolEscrow.t.sol:118-128
escrow.deposit(scId, asset, tokenId, 1000);  // total=1000
escrow.reserve(scId, asset, tokenId, 500);   // reserved=500
escrow.reserve(scId, asset, tokenId, 600);   // reserved=1100 > total=1000 ← 意図的
// withdraw(600) → revert (正しくブロック)
escrow.unreserve(scId, asset, tokenId, 600); // reserved=500, 回復
escrow.withdraw(scId, asset, tokenId, 500);  // 成功
```

3. **PoolEscrow.sol L66-68**: `availableBalanceOf()` が `total < reserved` を防御的に処理

```solidity
if (holding_.total < holding_.reserved) return 0;  // 想定済みの状態
```

4. **auth ゲート**: `reserve()` は authorized ward のみ呼び出し可能。README: "Pool manager roles are fully trusted within the context of the pool."

5. **recon-core ファジングターゲット**: `availableBalanceOf` にクランプして false positive を回避（チームは認識済み）

**Sherlock 提出判断**: Design Choice として却下される可能性が高い。Informational として提出する余地あり。

### F2: totalAssets() stale price — Known Issue

**判定: 既知の問題**

決定的証拠:

1. **README L76**: "Any arbitrage related to cross-chain price updates" — 包括的 known issue
2. **README L80**: "AsyncRequest._withdraw() using current pricePoolPerAsset which is potentially unlikely pricePoolPerAsset during approval of redemption"
3. **BaseVaults.sol L173-174 NatSpec**: "The actual conversion MAY change between order submission and execution"
4. **recon-core Properties.sol L233-243**: チーム自身が `property_totalAssets_solvency` を定義し、`totalAssets > actualAssets` をチェック済み
5. **recon-core Properties.sol L246-250**: `property_totalAssets_insolvency_only_increases` — 乖離の単調増加をモデル化（バグではなく特性として扱い）

**Sherlock 提出判断**: Invalid（既知問題）。提出すべきでない。

---

## 総括

| Failure | 根本原因 | 判定 | Sherlock |
|---------|---------|------|----------|
| Echidna: PE-1 | `reserve()` bounds check なし | Design Choice | △ Info |
| Echidna: CS-3 | 同上（PE-1 と同根因） | Design Choice | △ Info |
| Medusa: totalAssets | stale cache price | Known Issue | ✗ Invalid |

3件とも「新規脆弱性」としては提出困難。ただし E2E ファジングの価値として:

- **P-CS-1,2,4,5,6,7 が pass** → Hub↔Spoke 非同期アーキテクチャの基本的健全性を実証
- **Design Choice の検証** → `reserved > total` 許容がシステム全体で安全であることを確認
- **回帰テスト基盤** → 今後のコード変更時に E2E レベルでの不変条件検証が可能
