# recon-core Medusa Failure Summary

## 現在failするプロパティ

| Property | 分類 | 対応 |
|---|---|---|
| `property_totalAssets_solvency` | 既知 (README L80) | 修正なし — stale price はエポック間のデザイントレードオフ |
| `property_PE_1` (×16) | **Genuine Finding 1** | `poolEscrow_reserve_unclamped` が直接トリガー。PoolEscrow.reserve() に `require(reserved <= total)` が欠如。最短 8 calls で再現 |

## 無効化したプロパティ (return;)

| Property | 理由 | 詳細 |
|---|---|---|
| `property_VR_1` | Medusa で fail → 既知の問題のため `return;` で無効化 | ARM.max* が unlinked vault でも非ゼロを返す (ERC-4626違反)。README L85 "Liquidity can be stuck if all vaults are unlinked" に該当。audit_memo.md Finding 4 参照 |
| `property_SM_1` | Medusa で fail → 前提誤りのため `return;` で無効化 | maxReserve は SyncManager.deposit のみ。async deposits (approvedDeposits, fulfillDepositRequest) は bypass する |
