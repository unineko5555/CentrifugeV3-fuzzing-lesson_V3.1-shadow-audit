# Hub Suite Coverage Analysis (Medusa Long Run)

**Corpus**: 5213 entries | **Failures**: 0 | **Overall**: 66.1% (586/886 lines)

## Summary

| Contract | Lines | Hit | L% | Status |
|---|---|---|---|---|
| **BRM** | 385 | 340 | **88.3%** | GOOD |
| IdentityVal | 7 | 6 | **85.7%** | GOOD |
| Reentrancy | 4 | 4 | **100%** | GOOD |
| HubRegistry | 48 | 34 | **70.8%** | FAIR |
| ShareClassMgr | 55 | 36 | **65.5%** | MED |
| Accounting | 56 | 36 | **64.3%** | MED |
| Auth | 9 | 5 | **55.6%** | MED |
| Hub | 185 | 81 | **43.8%** | LOW |
| Holdings | 83 | 32 | **38.6%** | LOW |
| HubHandler | 34 | 9 | **26.5%** | CRIT |
| OracleVal | 20 | 3 | **15.0%** | CRIT |
| NAVManager | — | — | **N/A** | CRIT |

## Root Cause Analysis

### 1. HubHandler (26.5%) — Gateway callback functions completely uncovered

**Covered**: constructor + `file` only (setup時のみ, MaxHit=1)

**Uncovered**:
- `updateHoldingAmount` (L88-96) — Holdings.increase/decrease + Hub.updateAccountingAmount を呼ぶ最重要関数
- `updateShares` (L109-111) — ShareClassManager.updateShares を呼ぶ
- `request` (L70-73) — HubRequestManager へのリクエスト転送
- `initiateTransferShares` (L125-134) — クロスチェーンシェア転送

**原因**: 全て `auth` modifier 付き。Gateway コールバック設計のため、ファザーの sender に ward がない。

### 2. OracleValuation (15.0%) — feeder/manager 未設定

**Covered**: constructor + feeder mapping read のみ

**Uncovered**:
- `updateFeeder` (L41-43) — `hubRegistry.manager(poolId, msg.sender)` チェックで revert
- `setPrice` (L52-57) — `feeder[poolId][msg.sender]` チェックで revert
- `getPrice`/`getQuote` — setPrice が通らないので price 未設定 → `PriceNotSet` revert

### 3. Hub (43.8%) — Cross-chain sender + accounting 関数未到達

**Uncovered 104 lines** の内訳:
- **L123-173**: `notifyShareMetadata`, `updateShareHook`, `notifySharePrice`, `notifyAssetPrice`, `setMaxAssetPriceAge` — 全て sender.send* で Gateway に送信する関数
- **L285-310**: `updateVault`, `updateContract` — Spoke 側コントラクト更新
- **L464-480**: `setPoolAdapters`, `updateGatewayManager` — アダプター管理
- **L523-577**: `_updateAccountingAmount`, `_updateAccountingValue` — HubHandler 経由で呼ばれるが HubHandler が未カバーのため連鎖的に未到達
- **L603-617**: `holdingAccounts`, `liabilityAccounts`, `pricePoolPerAsset` — view 関数

### 4. Holdings (38.6%) — increase/decrease が未到達

**Covered**: initialize (L51-64), update (L190-202), value (L215-217) — setup + shortcut 経由

**Uncovered**:
- `setAccountId` (L72-77), `updateValuation` (L82-89), `updateIsLiability` (L94-100) — auth 関数
- `increase` (L156-165), `decrease` (L174-183) — HubHandler.updateHoldingAmount 経由のみ
- `setSnapshot` (L115-123) — HubHandler 経由のみ

### 5. NAVManager — カバレッジデータなし

lcov.info に含まれていない。バイトコードマッチング失敗 or ターゲット未到達。

## Priority Fixes

| # | Fix | Unlocks | Expected Impact |
|---|---|---|---|
| **1** | `hubHandler.rely(this)` + HubHandler ターゲット追加 | Holdings increase/decrease, Hub._updateAccountingAmount/Value, setSnapshot | +15-20% |
| **2** | OracleVal feeder/manager setup + setPrice ターゲット | OracleVal全体, Hub.updateHoldingValue, Holdings.update chain | +5-8% |
| **3** | Hub sender functions ターゲット追加 | notifySharePrice, notifyAssetPrice, updateShareHook 等 | +8-12% |
| **4** | ShareClassManager auth ターゲット追加 | addShareClass, updateSharePrice, updateShares | +3-5% |
| **5** | NAVManager 調査 + 修正 | NAVManager 全体 | TBD |

**Fix #1 + #2 で 66% → 85%+ が見込めます。**
