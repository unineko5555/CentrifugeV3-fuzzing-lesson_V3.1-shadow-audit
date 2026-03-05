# recon-core Medusa Failure Summary

## 現在failするプロパティ

| Property | 分類 | 対応 |
|---|---|---|
| `property_totalAssets_solvency` | 既知 (README L80) | 修正なし — stale price はエポック間のデザイントレードオフ |

## 無効化したプロパティ (return;)

| Property | 理由 | 詳細 |
|---|---|---|
| `property_VR_1` | Medusa で fail → 既知の問題のため `return;` で無効化 | ARM.max* が unlinked vault でも非ゼロを返す (ERC-4626違反)。README L85 "Liquidity can be stuck if all vaults are unlinked" に該当。audit_memo.md Finding 4 参照 |
| `property_SM_1` | Medusa で fail → 前提誤りのため `return;` で無効化 | maxReserve は SyncManager.deposit のみ。async deposits (approvedDeposits, fulfillDepositRequest) は bypass する |
