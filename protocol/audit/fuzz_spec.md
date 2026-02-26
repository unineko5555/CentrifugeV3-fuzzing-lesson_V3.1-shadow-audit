# Centrifuge Protocol v3.1 — Recon Chimera Fuzzing Specification

## 目次

1. [概要と方針](#1-概要と方針)
2. [v3→v3.1 アーキテクチャ変更サマリー](#2-v3v31-アーキテクチャ変更サマリー)
3. [Suite 1: recon-hub — Hub会計・エポック処理](#3-suite-1-recon-hub)
4. [Suite 2: recon-core — Spoke側Vault・リクエスト処理](#4-suite-2-recon-core)
5. [Suite 3: recon-e2e — Hub+Spoke統合テスト](#5-suite-3-recon-e2e)
6. [Suite 4: recon-aggregator — Gatewayメッセージルーティング](#6-suite-4-recon-aggregator)
7. [Echidna/Medusa設定](#7-echidnamedusa設定)
8. [実装優先度とロードマップ](#8-実装優先度とロードマップ)

---

## 1. 概要と方針

### 1.1 目的

Centrifuge Protocol v3.1 の Sherlock 監査コンテスト（Contest 1028, 320,000 USDC）に対し、
Recon Chimera フレームワークを用いた stateful fuzzing テストスイートを構築する。

v3 の既存 Recon fuzzing（4スイート、79ファイル）を基盤とし、v3.1 で新規追加・仕様変更された
コントラクトに対応する形でアダプテーションを行う。

### 1.2 Chimera アーキテクチャ（継承チェーン）

```
BaseSetup (setup関数)
    ↓
BeforeAfter (ghost変数・前後状態キャプチャ)
    ↓
Properties (不変条件・プロパティ定義)
    ↓
TargetFunctions (ファザー呼び出し対象関数)
    ↓
CryticTester (Echidna/Medusa用) + CryticToFoundry (Foundry用)
```

### 1.3 基本設計原則

| 原則 | 説明 |
|------|------|
| **Ghost Accounting** | オンチェーン状態と独立したゴースト変数で会計追跡 |
| **Clamped/Unclamped** | 各ターゲットに有効値域制限版と無制限版の2パターン |
| **Shortcut Functions** | 複数ステップの操作を1関数に集約（create_pool_and_deposit等） |
| **Toggle Pattern** | フラグ切替で異なるコードパスを網羅 |
| **OpType分類** | 操作種別をenumで分類し、種別別プロパティ検証 |
| **stateless modifier** | 状態変更なしの純粋検証をmodifier内で実行 |
| **Differential Fuzzing** | 2つの実装を並行実行して結果比較 |

### 1.4 v3スイート構成（参照元）

| スイート | ファイル数 | Real | Mocked | 状態 |
|----------|-----------|------|--------|------|
| recon-hub | 17 | Hub, Accounting, Holdings, HubRegistry, ShareClassManager, HubHelpers, IdentityValuation | Gateway, Spoke, BalanceSheet, MessageDispatcher | 完全実装 |
| recon-core | 25 | Escrow, AsyncRequestManager, SyncRequestManager, Spoke, AsyncVault, ShareToken, BalanceSheet, FullRestrictions | Hub, Gateway, MessageProcessor | 完全実装 |
| recon-e2e | 28 | Hub+Spoke両方 | Gateway/MessageDispatcher/MessageProcessor | 完全実装 |
| recon-aggregator | 9 | Gateway + 2 MockAdapters | Root, GasService | WIP/部分実装 |

---

## 2. v3→v3.1 アーキテクチャ変更サマリー

### 2.1 ファジングに影響する主要変更

| # | 変更 | 影響範囲 | Fuzzing上の意味 |
|---|------|---------|----------------|
| 1 | **BatchRequestManager新規追加（977行）** | Hub Suite, E2E | エポック処理がオンチェーン化。requestDeposit/Redeem、approveDeposits、issueShares、revokeShares、queued ordersの全フローをカバー必要 |
| 2 | **IHubRequestManagerプラグインシステム** | Hub Suite | Hub.executeRequest()→プラグインに委譲。Hub直接のprocessDepositRequest等は廃止 |
| 3 | **ShareClassManager 82%コード削減** | Hub Suite | エポックロジックがBatchRequestManagerに移動。ShareClassManagerは純粋なメタデータ管理のみ |
| 4 | **HubHelpers→HubHandler** | Hub Suite | クロスチェーンメッセージハンドラーに昇格。updateHoldingAmount, updateShares, request等 |
| 5 | **Accounting: EIP-1153トランジェントストレージ** | Hub Suite | debited/credited/currentPoolIdがトランジェント。lock()でdebited==credited検証 |
| 6 | **Holdings: Snapshotノンス、isLiabilityトグル** | Hub Suite | setSnapshot()にノンス検証追加、isLiability変更にはamount==0要件 |
| 7 | **msg.valueガス支払いモデル** | Core Suite, E2E | pool subsidy→msg.value直接払い。RefundEscrowで余剰返金 |
| 8 | **AsyncRequestManager: subsidy + trusted calls** | Core Suite | depositSubsidy/withdrawSubsidy、trustedCall分岐追加 |
| 9 | **SyncRequestManager→SyncManager** | Core Suite | ISyncDepositValuation、maxReserve追加 |
| 10 | **VaultRegistry分離（Spokeから）** | Core Suite | deployVault/linkVault/unlinkVault。マルチマネージャー対応 |
| 11 | **PoolEscrow新規（PerPoolエスクロー）** | Core Suite | total/reserved二重追跡。reserve/unreserve操作 |
| 12 | **BaseTransferHook（8転送フロー分類）** | Core Suite | checkERC20Transfer仮想関数。freeze/memberlist管理がhookData(bytes16)に統合 |
| 13 | **ShareToken: hookData, ERC-1404** | Core Suite | Balance構造体にhookData(bytes16)同居。authTransferFromでhookコールバック |
| 14 | **Gateway: withBatch(), unpaidMode** | Aggregator | バッチ送信パターン。TransientBytesLibで蓄積。msg.value分配 |
| 15 | **MessageLib: 27メッセージ型** | Aggregator | Generic Request/RequestCallback追加。14型→27型に拡大 |
| 16 | **Guardian分離: OpsGuardian + ProtocolGuardian** | E2E | pause/unpauseがProtocolGuardian、initAdapters/createPoolがOpsGuardian |
| 17 | **NAVManager新規** | Hub Suite, E2E | 会計アカウント初期化、NAV計算、gain/loss closure |
| 18 | **QueueManager新規** | E2E | minDelay制御のqueued assets/shares同期 |
| 19 | **OracleValuation新規** | Hub Suite | オラクルベース価格フィード。feeder権限管理 |
| 20 | **BalanceSheet: queuedShares/queuedAssets + transient price** | Core Suite, E2E | キュー状態追跡、overridePricePoolPerAsset/Share |

### 2.2 コントラクト名対応表

| v3 | v3.1 | 変更種別 |
|----|------|---------|
| `hub/Hub.sol` | `core/hub/Hub.sol` | 大幅変更（プラグイン委譲） |
| `hub/Accounting.sol` | `core/hub/Accounting.sol` | EIP-1153追加 |
| `hub/Holdings.sol` | `core/hub/Holdings.sol` | Snapshot nonce追加 |
| `hub/ShareClassManager.sol` | `core/hub/ShareClassManager.sol` | 82%削減 |
| `hub/PoolRegistry.sol` | `core/hub/HubRegistry.sol` | 名前変更+hubRequestManager追加 |
| `hub/HubHelpers.sol` | `core/hub/HubHandler.sol` | 完全置換 |
| — | `vaults/BatchRequestManager.sol` | **新規 (977行)** |
| — | `misc/RefundEscrow.sol` | **新規** |
| `spoke/Spoke.sol` | `core/spoke/Spoke.sol` | VaultRegistry分離 |
| — | `core/spoke/VaultRegistry.sol` | **新規** |
| — | `core/spoke/PoolEscrow.sol` | **新規** |
| `spoke/AsyncVault.sol` | `vaults/AsyncVault.sol` | ERC-7887追加 |
| `spoke/SyncRequestManager.sol` | `vaults/SyncManager.sol` | 名前変更+maxReserve |
| `spoke/BalanceSheet.sol` | `core/spoke/BalanceSheet.sol` | queue + transient price |
| `spoke/ShareToken.sol` | `core/spoke/ShareToken.sol` | hookData統合 |
| `common/Gateway.sol` | `core/messaging/Gateway.sol` | withBatch(), unpaidMode |
| — | `core/messaging/MessageProcessor.sol` | **新規** |
| — | `core/messaging/MessageDispatcher.sol` | **新規** |
| `common/Guardian.sol` | `core/admin/OpsGuardian.sol` + `ProtocolGuardian.sol` | 分離 |
| — | `hooks/BaseTransferHook.sol` | **新規 (258行)** |
| — | `managers/hub/NAVManager.sol` | **新規** |
| — | `managers/spoke/QueueManager.sol` | **新規** |
| — | `valuations/OracleValuation.sol` | **新規** |

---

## 3. Suite 1: recon-hub

### 3.1 ディレクトリ構造

```
protocol/test/hub/fuzzing/recon-hub/
├── Setup.sol                        [v3から大幅修正]
├── BeforeAfter.sol                  [v3から大幅修正]
├── Properties.sol                   [v3から修正+新規追加]
├── TargetFunctions.sol              [v3から修正]
├── CryticTester.sol                 [v3と同様]
├── CryticToFoundry.t.sol            [v3と同様]
├── targets/
│   ├── AdminTargets.sol             [v3から大幅修正]
│   ├── HubTargets.sol               [v3から修正]
│   ├── BatchRequestTargets.sol      [★新規]
│   ├── NAVTargets.sol               [★新規]
│   ├── ManagerTargets.sol           [v3から修正]
│   ├── ToggleTargets.sol            [v3から修正]
│   └── DoomsdayTargets.sol          [v3から修正]
├── helpers/
│   └── SharedStorage.sol            [v3から修正]
├── mocks/
│   ├── MockSpoke.sol                [v3から修正]
│   ├── MockBalanceSheet.sol         [v3から修正]
│   └── MockGateway.sol              [v3から修正]
├── echidna_hub.yaml                 [v3と同様]
└── medusa.json                      [v3と同様]
```

### 3.2 Setup.sol — デプロイメント設計

#### Real Contracts（実コントラクト）

```solidity
// ===== v3から継続（パス変更） =====
Root root;                              // core/admin/Root.sol
Accounting accounting;                  // core/hub/Accounting.sol
HubRegistry hubRegistry;               // core/hub/HubRegistry.sol (旧PoolRegistry)
Holdings holdings;                      // core/hub/Holdings.sol
Hub hub;                                // core/hub/Hub.sol
ShareClassManager shareClassManager;    // core/hub/ShareClassManager.sol
IdentityValuation identityValuation;    // valuations/IdentityValuation.sol

// ===== v3.1新規追加 =====
HubHandler hubHandler;                  // core/hub/HubHandler.sol (旧HubHelpers)
BatchRequestManager batchRequestManager; // vaults/BatchRequestManager.sol ★最重要
NAVManager navManager;                  // managers/hub/NAVManager.sol ★新規
OracleValuation oracleValuation;        // valuations/OracleValuation.sol ★新規
```

#### Mocked Contracts（モックコントラクト）

```solidity
// ===== v3から継続 =====
MockGateway gateway;                    // Gateway.sol のモック
MockSpoke spoke;                        // Spoke.sol のモック
MockBalanceSheet balanceSheet;          // BalanceSheet.sol のモック
MockMessageDispatcher dispatcher;       // MessageDispatcher.sol のモック

// ===== v3.1新規モック =====
MockAdapter adapter;                    // Adapter のモック（MultiAdapter用）
```

#### デプロイメントシーケンス

```solidity
function setup() internal override {
    // 1. Root & Registry
    root = new Root(address(this));
    hubRegistry = new HubRegistry(address(this));

    // 2. Core Hub contracts
    accounting = new Accounting(address(this));
    holdings = new Holdings(hubRegistry, address(this));
    shareClassManager = new ShareClassManager(hubRegistry, address(this));

    // 3. Mocks
    gateway = new MockGateway();
    adapter = new MockAdapter();
    spoke = new MockSpoke();
    balanceSheet = new MockBalanceSheet();
    dispatcher = new MockMessageDispatcher();

    // 4. Hub (v3.1 constructor: gateway, holdings, accounting, hubRegistry, multiAdapter, shareClassManager)
    hub = new Hub(
        IGateway(address(gateway)),
        holdings,
        accounting,
        hubRegistry,
        IMultiAdapter(address(adapter)),
        shareClassManager,
        address(this)
    );

    // 5. HubHandler (旧HubHelpers → 完全新規コンストラクタ)
    hubHandler = new HubHandler(
        hub,
        holdings,
        hubRegistry,
        shareClassManager,
        address(this)
    );

    // 6. ★ BatchRequestManager (最大の新規追加)
    batchRequestManager = new BatchRequestManager(address(this));
    batchRequestManager.file("hub", address(hub));

    // 7. ★ NAVManager
    navManager = new NAVManager(hub);

    // 8. Valuations
    identityValuation = new IdentityValuation(hubRegistry);
    oracleValuation = new OracleValuation(hub, hubRegistry);

    // 9. Permission wiring (rely)
    _setupPermissions();

    // 10. Actors (v3と同様: admin + 2 actors)
    _setupActors();
}

function _setupPermissions() internal {
    // Hub → HubHandler, BatchRequestManager
    hub.rely(address(hubHandler));
    hub.rely(address(batchRequestManager));
    hub.rely(address(navManager));

    // HubHandler → Hub
    hubHandler.file("sender", address(dispatcher));

    // Accounting → Hub
    accounting.rely(address(hub));

    // Holdings → Hub, HubHandler
    holdings.rely(address(hub));
    holdings.rely(address(hubHandler));

    // ShareClassManager → Hub, HubHandler
    shareClassManager.rely(address(hub));
    shareClassManager.rely(address(hubHandler));

    // HubRegistry → Hub
    hubRegistry.rely(address(hub));

    // BatchRequestManager → Hub
    batchRequestManager.rely(address(hub));

    // ★ HubRegistry: hubRequestManager設定
    // hubRegistry.setHubRequestManager(poolId, centrifugeId, batchRequestManager);
    // → PoolManager内で実行
}
```

#### v3 Setup.sol からの主な変更点

| v3 | v3.1 | 変更理由 |
|----|------|---------|
| `HubHelpers hubHelpers` | `HubHandler hubHandler` | 名前変更+コンストラクタ変更 |
| — | `BatchRequestManager batchRequestManager` | エポック処理がオンチェーン化 |
| — | `NAVManager navManager` | 会計アカウント管理の新規追加 |
| — | `OracleValuation oracleValuation` | オラクル価格フィードのテスト |
| `PoolRegistry` | `HubRegistry` | 名前変更+hubRequestManager追加 |
| `hub = new Hub(...)` | コンストラクタ引数変更 | multiAdapter追加、構造変更 |

### 3.3 BeforeAfter.sol — Ghost変数設計

#### v3から継続するGhost変数

```solidity
// ===== 会計ゴースト（v3と同様） =====
uint128 ghostDebited;           // トランザクション内の総借方
uint128 ghostCredited;          // トランザクション内の総貸方
uint128 ghostHolding;           // Holdings.amount の追跡
uint128 ghostAccountValue;      // Accounting.accountValue の追跡

// ===== エポックゴースト（v3と同様、ただしBatchRequestManager準拠に変更） =====
uint32 ghostEpochId_deposit;    // deposit epoch追跡
uint32 ghostEpochId_issue;      // issue epoch追跡
uint32 ghostEpochId_redeem;     // redeem epoch追跡
uint32 ghostEpochId_revoke;     // revoke epoch追跡
```

#### v3.1新規Ghost変数

```solidity
// ===== BatchRequestManager用ゴースト ★新規 =====

// Pending tracking per (poolId, scId, assetId)
uint128 ghostPendingDeposit;        // pendingDeposit の追跡
uint128 ghostPendingRedeem;         // pendingRedeem の追跡

// User order tracking per (poolId, scId, assetId, investor)
uint128 ghostUserDepositPending;    // UserOrder.pending (deposit)
uint128 ghostUserRedeemPending;     // UserOrder.pending (redeem)
uint32 ghostUserDepositLastUpdate;  // UserOrder.lastUpdate (deposit)
uint32 ghostUserRedeemLastUpdate;   // UserOrder.lastUpdate (redeem)

// Queued order tracking per (poolId, scId, assetId, investor)
bool ghostQueuedDepositCancelling;  // QueuedOrder.isCancelling (deposit)
uint128 ghostQueuedDepositAmount;   // QueuedOrder.amount (deposit)
bool ghostQueuedRedeemCancelling;   // QueuedOrder.isCancelling (redeem)
uint128 ghostQueuedRedeemAmount;    // QueuedOrder.amount (redeem)

// Epoch amounts tracking
uint128 ghostEpochApprovedAssetAmount;   // EpochInvestAmounts.approvedAssetAmount
uint128 ghostEpochApprovedShareAmount;   // EpochRedeemAmounts.approvedShareAmount
uint128 ghostEpochPendingAssetAmount;    // EpochInvestAmounts.pendingAssetAmount
uint128 ghostEpochPendingShareAmount;    // EpochRedeemAmounts.pendingShareAmount

// Force cancel flags
bool ghostAllowForceDepositCancel;  // BatchRequestManager.allowForceDepositCancel
bool ghostAllowForceRedeemCancel;   // BatchRequestManager.allowForceRedeemCancel

// ===== NAVManager用ゴースト ★新規 =====
uint128 ghostEquityValue;           // equityAccount の値
uint128 ghostLiabilityValue;        // liabilityAccount の値
uint128 ghostGainValue;             // gainAccount の値
uint128 ghostLossValue;             // lossAccount の値
uint128 ghostNAV;                   // 計算済みNAV

// ===== OracleValuation用ゴースト ★新規 =====
D18 ghostOraclePrice;               // OracleValuation.pricePoolPerAsset
bool ghostOraclePriceIsValid;       // Price.isValid フラグ

// ===== Accounting EIP-1153用ゴースト ★新規 =====
bool ghostAccountingLocked;         // currentPoolId == 0 かどうか
```

#### OpType enum変更

```solidity
// v3
enum OpType { GENERIC, DEPOSIT, REDEEM, BATCH }

// v3.1 (BatchRequestManager操作の細分化)
enum OpType {
    GENERIC,
    REQUEST_DEPOSIT,    // BatchRequestManager.requestDeposit
    REQUEST_REDEEM,     // BatchRequestManager.requestRedeem
    CANCEL_DEPOSIT,     // BatchRequestManager.cancelDepositRequest
    CANCEL_REDEEM,      // BatchRequestManager.cancelRedeemRequest
    APPROVE_DEPOSITS,   // BatchRequestManager.approveDeposits
    APPROVE_REDEEMS,    // BatchRequestManager.approveRedeems
    ISSUE_SHARES,       // BatchRequestManager.issueShares
    REVOKE_SHARES,      // BatchRequestManager.revokeShares
    CLAIM_DEPOSIT,      // BatchRequestManager.notifyDeposit (_claimDeposit)
    CLAIM_REDEEM,       // BatchRequestManager.notifyRedeem (_claimRedeem)
    FORCE_CANCEL,       // BatchRequestManager.forceCancel*
    NAV_UPDATE,         // NAVManager operations
    HOLDING_UPDATE,     // Holdings increase/decrease/update
    ADMIN               // Pool/ShareClass admin operations
}
```

#### __before/__after キャプチャ変更

```solidity
modifier updateGhostsWithType(OpType opType) {
    _before(opType);
    _;
    _after(opType);
}

function _before(OpType opType) internal {
    // === v3から継続 ===
    _ghostDebited_before = accounting.debited();
    _ghostCredited_before = accounting.credited();

    // === v3.1新規: BatchRequestManager状態キャプチャ ===
    if (poolIdIsSet && shareClassIdIsSet && assetIdIsSet) {
        _ghostPendingDeposit_before = batchRequestManager.pendingDeposit(poolId, scId, assetId);
        _ghostPendingRedeem_before = batchRequestManager.pendingRedeem(poolId, scId, assetId);

        (uint32 depEpoch, uint32 issEpoch, uint32 redEpoch, uint32 revEpoch) =
            batchRequestManager.epochId(poolId, scId, assetId);
        _ghostEpochId_deposit_before = depEpoch;
        _ghostEpochId_issue_before = issEpoch;
        _ghostEpochId_redeem_before = redEpoch;
        _ghostEpochId_revoke_before = revEpoch;
    }

    // === v3.1新規: NAV状態キャプチャ ===
    if (poolIdIsSet && centrifugeIdIsSet) {
        _ghostNAV_before = navManager.netAssetValue(poolId, centrifugeId);
    }
}
```

### 3.4 Properties.sol — 不変条件設計

#### v3から継続するプロパティ（修正あり）

```solidity
// P-HUB-1: 会計均衡（v3と同様だがEIP-1153対応）
// debited == credited at lock() time
// → Accounting.lock() が revert しないことを検証
property_accounting_balance_at_lock()

// P-HUB-2: Assets = accountValue(Asset)（v3と同様）
// Holdings.value(poolId, scId, assetId) == Accounting.accountValue(poolId, assetAccount)
property_holdings_accounting_consistency()

// P-HUB-3: yield equation（v3と同様）
// assets = equity + gain - loss
// ※ v3.1では NAVManager.netAssetValue() で計算可能
property_yield_equation()

// P-HUB-4: エポック単調増加（v3と同様だがBatchRequestManager準拠）
// epochId は前回値 +1 以下の増分のみ許可
// ※ v3.1では4つの独立エポック: deposit, issue, redeem, revoke
property_epoch_monotonicity()
```

#### v3.1新規プロパティ — BatchRequestManager

```solidity
// P-BRM-1: Pending一貫性
// pendingDeposit[poolId][scId][assetId] == Σ(userOrders where lastUpdate >= currentDepositEpoch).pending
// ※ 全ユーザーのpending合計 == グローバルpending
invariant_pending_deposit_consistency()

// P-BRM-2: Pending一貫性（Redeem）
// pendingRedeem[poolId][scId][assetId] == Σ(userOrders).pending
invariant_pending_redeem_consistency()

// P-BRM-3: Epoch順序制約
// deposit epoch <= issue epoch (発行にはapprovalが先行)
// redeem epoch <= revoke epoch (revokeにはapprovalが先行)
invariant_epoch_ordering()

// P-BRM-4: Approve上限
// approveDeposits の approvedAssetAmount <= 直前の pendingAssetAmount
// approveRedeems の approvedShareAmount <= 直前の pendingShareAmount
property_approve_bounded_by_pending()

// P-BRM-5: Queued Order整合性
// ユーザーのlastUpdate >= currentEpochの場合、追加リクエストはキューに入る
// キューに入ったリクエストはclaim後にpendingに移動
property_queued_order_lifecycle()

// P-BRM-6: Force Cancel前提条件
// forceCancelDepositRequest は allowForceDepositCancel == true の場合のみ成功
// allowForceDepositCancel は cancelDepositRequest 後、エポック跨ぎで設定される
property_force_cancel_requires_approval()

// P-BRM-7: Claim完全性
// claim後、ユーザーの maxDepositClaims/maxRedeemClaims が減少
// 全claim完了後 maxClaims == 0
property_claim_completeness()

// P-BRM-8: Issue/Revokeフロー整合性
// issueShares で発行されたシェア量 == Σ(approvedAssetAmount / pricePoolPerShare) for all claimable epochs
// revokeShares で revoke されたシェア量 == Σ(approvedShareAmount) for all claimable epochs
property_issue_revoke_consistency()

// P-BRM-9: エポック遷移アトミシティ
// approveDeposits → issueShares は必ずこの順序（IssuanceRequired エラーなし）
// approveRedeems → revokeShares は必ずこの順序（RevocationRequired エラーなし）
property_epoch_transition_atomicity()
```

#### v3.1新規プロパティ — Accounting EIP-1153

```solidity
// P-ACC-1: トランジェントロック一貫性
// unlock() 後、lock() までの間: debited と credited は任意に変化可能
// lock() 時: debited == credited でなければ revert
// ※ トランジェントストレージはtx終了時にリセット
property_transient_lock_consistency()

// P-ACC-2: Single Pool Lock
// 同一トランザクション内で2つの異なるpoolIdに対してunlock()は不可
// _currentPoolId が設定済みなら revert
property_single_pool_lock()

// P-ACC-3: Journal ID一意性
// 同一poolId内でjournalIdは単調増加
property_journal_id_uniqueness()
```

#### v3.1新規プロパティ — NAVManager

```solidity
// P-NAV-1: NAV計算整合性
// NAV = equity + gain - loss - liability（各accountValueから計算）
// navManager.netAssetValue(poolId, centrifugeId) == 手動計算値
property_nav_calculation_consistency()

// P-NAV-2: Gain/Loss Closure後
// closeGainLoss 後: gainAccount.value == 0 && lossAccount.value == 0
// equityAccount に移動済み
property_gain_loss_closure()

// P-NAV-3: Network初期化前提条件
// initializeHolding は initialized[poolId][centrifugeId] == true を要求
property_holding_requires_network_init()
```

#### v3.1新規プロパティ — Holdings

```solidity
// P-HOLD-1: Snapshot Nonce保護
// setSnapshot で nonce が一致しない場合 revert
// nonce は呼び出しごとに +1
property_snapshot_nonce_protection()

// P-HOLD-2: isLiability変更制約
// updateIsLiability は assetAmount == 0 && assetAmountValue == 0 の場合のみ成功
property_is_liability_requires_empty()

// P-HOLD-3: Holding value整合性
// Holdings.update() 後: assetAmountValue == valuation.getQuote(assetAmount)
property_holding_value_after_update()
```

#### v3.1新規プロパティ — OracleValuation

```solidity
// P-ORACLE-1: Feeder権限制約
// setPrice は feeder[poolId][msg.sender] == true の場合のみ成功
property_oracle_feeder_only()

// P-ORACLE-2: Price設定後の即時反映
// setPrice → hub.updateHoldingValue() が連鎖呼び出しされる
// Holdings.assetAmountValue が更新される
property_oracle_price_propagation()
```

### 3.5 TargetFunctions — ターゲット関数設計

#### targets/AdminTargets.sol（v3から修正）

```solidity
// v3から継続（名前変更あり）
function hub_createPool(PoolId poolId, address admin, AssetId currency) external;
function hub_addShareClass(PoolId poolId, string name, string symbol, bytes32 salt) external;

// v3から修正: BatchRequestManager経由に変更
// v3: hub.processDepositRequest() / hub.processRedeemRequest()
// v3.1: batchRequestManager.approveDeposits() / batchRequestManager.issueShares()
// → AdminTargets から BatchRequestTargets に移動

// v3.1新規
function hub_setRequestManager(PoolId poolId, uint16 centrifugeId, IHubRequestManager manager) external;
function hub_updateHubManager(PoolId poolId, address who, bool canManage) external;
function hub_initializeHolding(...) external;
function hub_initializeLiability(...) external;
function hub_updateHoldingValue(PoolId poolId, ShareClassId scId, AssetId assetId) external;
function hub_updateHoldingValuation(PoolId poolId, ShareClassId scId, AssetId assetId, IValuation) external;
function hub_updateAccountingAmount(PoolId poolId, ShareClassId scId, AssetId assetId, bool isPositive, uint128 diff) external;
function hub_updateAccountingValue(PoolId poolId, ShareClassId scId, AssetId assetId, bool isPositive, uint128 diff) external;
function hub_updateJournal(PoolId poolId, JournalEntry[] debits, JournalEntry[] credits) external;
```

#### targets/BatchRequestTargets.sol（★完全新規）

```solidity
// ===== ユーザーリクエスト =====

function brm_requestDeposit(
    uint128 amount       // clamped: 1 ~ type(uint128).max / 2
) external updateGhostsWithType(OpType.REQUEST_DEPOSIT) asActor {
    amount = uint128(between(uint256(amount), 1, type(uint128).max / 2));
    bytes32 investor = _actorToBytes32(currentActor);

    // Pre-condition: can mutate pending
    (uint128 pending, uint32 lastUpdate) = batchRequestManager.depositRequest(poolId, scId, assetId, investor);

    batchRequestManager.requestDeposit(poolId, scId, amount, investor, assetId);

    // Post-condition ghost update
    ghostPendingDeposit += amount;
    ghostUserDepositPending += amount;
}

function brm_requestRedeem(
    uint128 amount
) external updateGhostsWithType(OpType.REQUEST_REDEEM) asActor {
    amount = uint128(between(uint256(amount), 1, type(uint128).max / 2));
    bytes32 investor = _actorToBytes32(currentActor);

    batchRequestManager.requestRedeem(poolId, scId, amount, investor, assetId);

    ghostPendingRedeem += amount;
    ghostUserRedeemPending += amount;
}

function brm_cancelDepositRequest()
    external updateGhostsWithType(OpType.CANCEL_DEPOSIT) asActor
{
    bytes32 investor = _actorToBytes32(currentActor);
    uint128 cancelledAmount = batchRequestManager.cancelDepositRequest(poolId, scId, investor, assetId);

    ghostPendingDeposit -= cancelledAmount;
    ghostUserDepositPending = 0;
}

function brm_cancelRedeemRequest()
    external updateGhostsWithType(OpType.CANCEL_REDEEM) asActor
{
    bytes32 investor = _actorToBytes32(currentActor);
    uint128 cancelledAmount = batchRequestManager.cancelRedeemRequest(poolId, scId, investor, assetId);

    ghostPendingRedeem -= cancelledAmount;
    ghostUserRedeemPending = 0;
}

// ===== マネージャー操作 =====

function brm_approveDeposits(
    uint128 approvedAmount,
    uint256 priceRaw         // clamped: 1e15 ~ 2e18
) external updateGhostsWithType(OpType.APPROVE_DEPOSITS) asAdmin {
    uint32 nowDepositEpoch = batchRequestManager.nowDepositEpoch(poolId, scId, assetId);
    uint128 currentPending = batchRequestManager.pendingDeposit(poolId, scId, assetId);

    approvedAmount = uint128(between(uint256(approvedAmount), 1, currentPending));
    D18 pricePoolPerAsset = d18(between(priceRaw, 1e15, 2e18));

    batchRequestManager.approveDeposits(
        poolId, scId, assetId, nowDepositEpoch, approvedAmount, pricePoolPerAsset, address(this)
    );

    ghostEpochApprovedAssetAmount = approvedAmount;
}

function brm_issueShares(
    uint256 priceRaw
) external updateGhostsWithType(OpType.ISSUE_SHARES) asAdmin {
    uint32 nowIssueEpoch = batchRequestManager.nowIssueEpoch(poolId, scId, assetId);
    D18 pricePoolPerShare = d18(between(priceRaw, 1e15, 2e18));

    batchRequestManager.issueShares(
        poolId, scId, assetId, nowIssueEpoch, pricePoolPerShare, 0, address(this)
    );
}

function brm_approveRedeems(
    uint128 approvedAmount,
    uint256 priceRaw
) external updateGhostsWithType(OpType.APPROVE_REDEEMS) asAdmin {
    uint32 nowRedeemEpoch = batchRequestManager.nowRedeemEpoch(poolId, scId, assetId);
    uint128 currentPending = batchRequestManager.pendingRedeem(poolId, scId, assetId);

    approvedAmount = uint128(between(uint256(approvedAmount), 1, currentPending));
    D18 pricePoolPerAsset = d18(between(priceRaw, 1e15, 2e18));

    batchRequestManager.approveRedeems(
        poolId, scId, assetId, nowRedeemEpoch, approvedAmount, pricePoolPerAsset
    );

    ghostEpochApprovedShareAmount = approvedAmount;
}

function brm_revokeShares(
    uint256 priceRaw
) external updateGhostsWithType(OpType.REVOKE_SHARES) asAdmin {
    uint32 nowRevokeEpoch = batchRequestManager.nowRevokeEpoch(poolId, scId, assetId);
    D18 pricePoolPerShare = d18(between(priceRaw, 1e15, 2e18));

    batchRequestManager.revokeShares(
        poolId, scId, assetId, nowRevokeEpoch, pricePoolPerShare, 0, address(this)
    );
}

// ===== Claim操作 =====

function brm_notifyDeposit(
    uint32 maxClaims
) external updateGhostsWithType(OpType.CLAIM_DEPOSIT) asActor {
    bytes32 investor = _actorToBytes32(currentActor);
    uint32 available = batchRequestManager.maxDepositClaims(poolId, scId, investor, assetId);
    maxClaims = uint32(between(uint256(maxClaims), 1, available > 0 ? available : 1));

    batchRequestManager.notifyDeposit(poolId, scId, assetId, investor, maxClaims, address(this));
}

function brm_notifyRedeem(
    uint32 maxClaims
) external updateGhostsWithType(OpType.CLAIM_REDEEM) asActor {
    bytes32 investor = _actorToBytes32(currentActor);
    uint32 available = batchRequestManager.maxRedeemClaims(poolId, scId, investor, assetId);
    maxClaims = uint32(between(uint256(maxClaims), 1, available > 0 ? available : 1));

    batchRequestManager.notifyRedeem(poolId, scId, assetId, investor, maxClaims, address(this));
}

// ===== Force Cancel =====

function brm_forceCancelDepositRequest()
    external updateGhostsWithType(OpType.FORCE_CANCEL) asAdmin
{
    bytes32 investor = _actorToBytes32(currentActor);
    batchRequestManager.forceCancelDepositRequest(poolId, scId, investor, assetId, address(this));
}

function brm_forceCancelRedeemRequest()
    external updateGhostsWithType(OpType.FORCE_CANCEL) asAdmin
{
    bytes32 investor = _actorToBytes32(currentActor);
    batchRequestManager.forceCancelRedeemRequest(poolId, scId, investor, assetId, address(this));
}

// ===== Shortcuts（複合操作） =====

function shortcut_deposit_approve_issue_claim(
    uint128 depositAmount,
    uint256 approvePrice,
    uint256 issuePrice
) external asAdmin {
    // 1. requestDeposit
    brm_requestDeposit(depositAmount);
    // 2. approveDeposits
    brm_approveDeposits(depositAmount, approvePrice);
    // 3. issueShares
    brm_issueShares(issuePrice);
    // 4. notifyDeposit
    brm_notifyDeposit(1);
}

function shortcut_redeem_approve_revoke_claim(
    uint128 redeemAmount,
    uint256 approvePrice,
    uint256 revokePrice
) external asAdmin {
    brm_requestRedeem(redeemAmount);
    brm_approveRedeems(redeemAmount, approvePrice);
    brm_revokeShares(revokePrice);
    brm_notifyRedeem(1);
}
```

#### targets/NAVTargets.sol（★完全新規）

```solidity
function nav_initializeNetwork(uint16 centrifugeId)
    external updateGhostsWithType(OpType.NAV_UPDATE) asAdmin
{
    navManager.initializeNetwork(poolId, centrifugeId);
}

function nav_initializeHolding(IValuation valuation)
    external updateGhostsWithType(OpType.NAV_UPDATE) asAdmin
{
    navManager.initializeHolding(poolId, scId, assetId, valuation);
}

function nav_initializeLiability(IValuation valuation)
    external updateGhostsWithType(OpType.NAV_UPDATE) asAdmin
{
    navManager.initializeLiability(poolId, scId, assetId, valuation);
}

function nav_updateHoldingValue()
    external updateGhostsWithType(OpType.NAV_UPDATE) asAdmin
{
    navManager.updateHoldingValue(poolId, scId, assetId);
}

function nav_closeGainLoss(uint16 centrifugeId)
    external updateGhostsWithType(OpType.NAV_UPDATE) asAdmin
{
    navManager.closeGainLoss(poolId, centrifugeId);
}

function nav_setOraclePrice(uint256 priceRaw)
    external updateGhostsWithType(OpType.NAV_UPDATE) asAdmin
{
    D18 price = d18(between(priceRaw, 1, 10e18));
    oracleValuation.setPrice(poolId, scId, assetId, price);
}
```

#### targets/ToggleTargets.sol（v3から修正）

```solidity
// v3から継続
function toggle_IS_LIABILITY() external;
function toggle_IS_INCREASE() external;
function toggle_IS_DEBIT_NORMAL() external;
function toggle_NONCE() external;

// v3.1新規
function toggle_IS_SNAPSHOT() external;
function toggle_USE_ORACLE_VALUATION() external;  // IdentityValuation ↔ OracleValuation切替
function toggle_ASSET_ID() external;              // 複数AssetId間の切替
function toggle_CENTRIFUGE_ID() external;         // 複数CentrifugeId間の切替
```

#### targets/DoomsdayTargets.sol（v3から修正）

```solidity
// v3から継続
function doomsday_accountValue_liveness() external;
function doomsday_differential_int128_uint128() external;

// v3.1新規
function doomsday_batchRequestManager_rounding()
    external stateless
{
    // BatchRequestManager の丸め検証
    // 預入→approve→issue→claim の往復で資産が増加しないことを検証
    // プロトコル有利な丸め（ユーザー不利）が一貫しているか
}

function doomsday_nav_manipulation()
    external stateless
{
    // NAV操作耐性検証
    // Oracle価格変更 → NAV計算 → Holdings再評価 の一連で
    // 不正利益が発生しないことを検証
}

function doomsday_epoch_queue_manipulation()
    external stateless
{
    // エポック中のキュー操作検証
    // エポック処理中にリクエスト追加→キュー→claim後のpending移動で
    // 資産が二重カウントされないことを検証
}
```

### 3.6 Shortcut一覧

| Shortcut名 | 操作シーケンス | 目的 |
|------------|---------------|------|
| `create_pool_and_holding` | createPool → addShareClass → registerAsset → initializeNetwork → initializeHolding | Holdingセットアップの短縮 |
| `deposit_full_cycle` | requestDeposit → approveDeposits → issueShares → notifyDeposit | 預入フルサイクル |
| `redeem_full_cycle` | requestRedeem → approveRedeems → revokeShares → notifyRedeem | 償還フルサイクル |
| `deposit_and_cancel` | requestDeposit → cancelDepositRequest | 預入キャンセルフロー |
| `deposit_queue_and_claim` | requestDeposit (during epoch) → approve → issue → claim → queue moves to pending | キュー経由フロー |
| `oracle_price_update` | setPrice → updateHoldingValue → check NAV | Oracle価格更新サイクル |

---

## 4. Suite 2: recon-core

### 4.1 ディレクトリ構造

```
protocol/test/vaults/fuzzing/recon-core/
├── Setup.sol                        [v3から大幅修正]
├── BeforeAfter.sol                  [v3から大幅修正]
├── properties/
│   ├── Properties.sol               [v3から修正+新規追加]
│   ├── AsyncVaultProperties.sol     [v3から修正]
│   ├── AsyncVaultCentrifugeProperties.sol [v3から修正]
│   ├── PoolEscrowProperties.sol     [★新規]
│   ├── TransferHookProperties.sol   [★新規]
│   ├── SyncManagerProperties.sol    [★新規]
│   ├── VaultRegistryProperties.sol  [★新規]
│   └── RefundEscrowProperties.sol   [★新規]
├── targets/
│   ├── VaultTargets.sol             [v3から修正]
│   ├── VaultCallbackTargets.sol     [v3から修正]
│   ├── GatewayMockTargets.sol       [v3から修正]
│   ├── ShareTokenTargets.sol        [v3から修正]
│   ├── TransferHookTargets.sol      [★新規 (旧FullRestrictionsTargets)]
│   ├── PoolEscrowTargets.sol        [★新規]
│   ├── VaultRegistryTargets.sol     [★新規]
│   ├── SyncManagerTargets.sol       [★新規]
│   ├── BalanceSheetTargets.sol      [★新規 (queue操作)]
│   ├── ManagerTargets.sol           [v3から修正]
│   ├── PoolManagerTargets.sol       [v3から修正]
│   └── DoomsdayTargets.sol          [v3から修正]
├── helpers/
│   ├── Ghosts.sol                   [v3から修正]
│   └── SharedStorage.sol            [v3から大幅修正]
├── mocks/
│   ├── MockHub.sol                  [v3から修正]
│   ├── MockGateway.sol              [v3から修正]
│   └── MockMessageProcessor.sol     [v3から修正]
├── CryticTester.sol                 [v3と同様]
├── CryticToFoundry.t.sol            [v3と同様]
├── echidna_core.yaml                [v3と同様]
└── medusa.json                      [v3と同様]
```

### 4.2 Setup.sol — デプロイメント設計

#### Real Contracts

```solidity
// ===== v3から継続（パス変更） =====
Root root;
Escrow globalEscrow;                        // misc/Escrow.sol (グローバル)
AsyncRequestManager asyncRequestManager;    // vaults/AsyncRequestManager.sol
Spoke spoke;                                // core/spoke/Spoke.sol
AsyncVault asyncVault;                      // vaults/AsyncVault.sol
ShareToken shareToken;                      // core/spoke/ShareToken.sol
BalanceSheet balanceSheet;                  // core/spoke/BalanceSheet.sol
TokenFactory tokenFactory;
AsyncVaultFactory asyncVaultFactory;

// ===== v3.1新規追加 =====
PoolEscrow poolEscrow;                      // core/spoke/PoolEscrow.sol ★新規
VaultRegistry vaultRegistry;                // core/spoke/VaultRegistry.sol ★新規
SyncManager syncManager;                    // vaults/SyncManager.sol (旧SyncRequestManager)
RefundEscrow refundEscrow;                  // vaults/RefundEscrow.sol ★新規
PoolEscrowFactory poolEscrowFactory;        // ★新規
RefundEscrowFactory refundEscrowFactory;    // ★新規

// ===== Hooks (1つ選択) =====
FullRestrictions fullRestrictions;          // hooks/FullRestrictions.sol
// または FreelyTransferable, FreezeOnly, RedemptionRestrictions
```

#### Mocked Contracts

```solidity
MockHub hub;
MockGateway gateway;
MockMessageProcessor processor;
MockMessageDispatcher dispatcher;   // ★新規モック
```

#### デプロイメントシーケンス

```solidity
function setup() internal override {
    // 1. Root & Global Escrow
    root = new Root(address(this));
    globalEscrow = new Escrow(address(this));

    // 2. Mocks
    gateway = new MockGateway();
    hub = new MockHub();
    processor = new MockMessageProcessor();
    dispatcher = new MockMessageDispatcher();

    // 3. Factories
    tokenFactory = new TokenFactory(address(this));
    poolEscrowFactory = new PoolEscrowFactory(address(this));
    asyncVaultFactory = new AsyncVaultFactory(address(root));
    refundEscrowFactory = new RefundEscrowFactory(address(this));

    // 4. Spoke (v3.1: tokenFactory引数のみ)
    spoke = new Spoke(tokenFactory, address(this));
    spoke.file("gateway", address(gateway));
    spoke.file("sender", address(dispatcher));
    spoke.file("poolEscrowFactory", address(poolEscrowFactory));

    // 5. ★ VaultRegistry (Spokeから分離)
    vaultRegistry = new VaultRegistry(address(this));
    vaultRegistry.file("spoke", address(spoke));

    // 6. BalanceSheet (v3.1: endorsements引数追加)
    balanceSheet = new BalanceSheet(IEndorsements(address(root)), address(this));
    balanceSheet.file("spoke", address(spoke));
    balanceSheet.file("sender", address(dispatcher));
    balanceSheet.file("poolEscrowProvider", address(spoke));

    // 7. ★ RefundEscrow
    refundEscrow = new RefundEscrow(address(this));

    // 8. AsyncRequestManager (v3.1: globalEscrow, refundEscrowFactory引数)
    asyncRequestManager = new AsyncRequestManager(
        globalEscrow,
        refundEscrowFactory,
        address(this)
    );
    asyncRequestManager.file("spoke", address(spoke));
    asyncRequestManager.file("balanceSheet", address(balanceSheet));
    asyncRequestManager.file("vaultRegistry", address(vaultRegistry));

    // 9. ★ SyncManager (旧SyncRequestManager)
    syncManager = new SyncManager(address(this));
    syncManager.file("spoke", address(spoke));
    syncManager.file("vaultRegistry", address(vaultRegistry));
    syncManager.file("balanceSheet", address(balanceSheet));

    // 10. Hook (v3.1: BaseTransferHook引数: root, spoke, redeemSource, depositTarget, crosschainSource)
    fullRestrictions = new FullRestrictions(
        root,
        spoke,
        address(globalEscrow),       // redeemSource
        address(balanceSheet),       // depositTarget
        address(spoke)               // crosschainSource
    );

    // 11. Pool & ShareClass初期化
    _initializePoolAndVault();

    // 12. Permissions
    _setupPermissions();

    // 13. Actors
    _setupActors();
}
```

#### v3からの主な変更点

| v3 | v3.1 | 変更理由 |
|----|------|---------|
| `SyncRequestManager` | `SyncManager` | 名前変更+ISyncDepositValuation追加 |
| Vault登録はSpoke内 | `VaultRegistry` 独立 | マルチマネージャー対応 |
| — | `PoolEscrow` | per-pool escrow (total/reserved二重追跡) |
| — | `RefundEscrow` + factory | msg.value返金メカニズム |
| `FullRestrictions(root)` | `FullRestrictions(root, spoke, ...)` | BaseTransferHookのコンストラクタ変更 |
| `BalanceSheet(deployer)` | `BalanceSheet(endorsements, deployer)` | endorsement checkの追加 |
| `AsyncRequestManager(escrow, deployer)` | `AsyncRequestManager(escrow, refundFactory, deployer)` | subsidy/refund追加 |

### 4.3 BeforeAfter.sol — Ghost変数設計

#### v3から継続するGhost変数

```solidity
// Per-actor investment state
struct AsyncInvestmentStateGhost {
    uint128 maxDeposit;
    uint128 maxMint;
    uint128 maxWithdraw;
    uint128 maxRedeem;
    uint128 pendingDepositRequest;
    uint128 pendingRedeemRequest;
    bool pendingCancelDepositRequest;
    bool pendingCancelRedeemRequest;
    uint128 claimableCancelDepositRequest;
    uint128 claimableCancelRedeemRequest;
}

mapping(address => AsyncInvestmentStateGhost) _ghostInvestmentState_before;
mapping(address => AsyncInvestmentStateGhost) _ghostInvestmentState_after;

uint256 ghostEscrowTokenBalance;
uint256 ghostEscrowTrancheTokenBalance;
uint256 ghostTotalAssets;
uint256 ghostActualAssets;
D18 ghostPricePerShare;
uint256 ghostTotalShareSupply;
```

#### v3.1新規Ghost変数

```solidity
// ===== PoolEscrow用ゴースト ★新規 =====
mapping(AssetId => uint128) ghostPoolEscrowTotal;       // PoolEscrow.holding.total
mapping(AssetId => uint128) ghostPoolEscrowReserved;    // PoolEscrow.holding.reserved
mapping(AssetId => uint128) ghostPoolEscrowAvailable;   // total - reserved

// ===== BalanceSheet Queue用ゴースト ★新規 =====
int128 ghostQueuedSharesDelta;      // queuedShares の net delta
uint64 ghostQueuedSharesCounter;    // queuedShares の counter
mapping(AssetId => int128) ghostQueuedAssetsDelta;      // per-asset delta
mapping(AssetId => uint64) ghostQueuedAssetsCounter;    // per-asset counter

// ===== TransferHook用ゴースト ★新規 =====
mapping(address => bool) ghostIsFrozen;         // per-user freeze state
mapping(address => uint64) ghostValidUntil;     // per-user memberlist expiry
mapping(address => bytes16) ghostHookData;      // raw hookData

// ===== SyncManager用ゴースト ★新規 =====
mapping(AssetId => uint128) ghostMaxReserve;    // per-asset max reserve
address ghostSyncValuation;                      // ISyncDepositValuation address

// ===== VaultRegistry用ゴースト ★新規 =====
mapping(address => bool) ghostVaultLinked;       // vault → linked status
mapping(address => AssetId) ghostVaultAssetId;   // vault → assetId

// ===== RefundEscrow用ゴースト ★新規 =====
uint256 ghostRefundEscrowBalance;                // native balance

// ===== Subsidy用ゴースト ★新規 =====
mapping(PoolId => uint256) ghostSubsidyBalance;  // per-pool subsidy
```

#### Per-actor ghost構造体の拡張

```solidity
// v3のGhosts.sol に追加
struct PriceEnvelope {
    D18 maxDepositPrice;
    D18 minDepositPrice;
    D18 maxRedeemPrice;
    D18 minRedeemPrice;
}

// v3.1追加
struct TransferHookState {
    bool isFrozen;
    uint64 validUntil;
    bool isEndorsed;
}
```

### 4.4 Properties — 不変条件設計

#### v3から継続するプロパティ

```solidity
// ERC-7540 標準プロパティ（v3 AsyncVaultProperties.sol と同様）
// P-7540-1: convertToAssets(totalSupply) == totalAssets
// P-7540-2: maxDeposit never reverts
// P-7540-3: maxMint never reverts
// P-7540-4: maxRedeem never reverts
// P-7540-5: maxWithdraw never reverts
// P-7540-6: previewDeposit always reverts (async)
// P-7540-7: previewMint always reverts (async)

// エスクロー会計プロパティ（v3 Properties.sol と同様）
// P-E-1: escrow.balanceOf(token) >= sumOfPendingDeposits
// P-E-2: escrow.balanceOf(trancheToken) >= sumOfPendingRedeems
// P-E-3: actual token balance >= escrow accounting
// P-E-4: ghost accounting == escrow accounting
```

#### properties/PoolEscrowProperties.sol（★完全新規）

```solidity
// P-PE-1: PoolEscrow Solvency
// PoolEscrow.holding.total >= PoolEscrow.holding.reserved
// ※ available = total - reserved >= 0 (underflowなし)
invariant_pool_escrow_total_gte_reserved()

// P-PE-2: PoolEscrow Balance Consistency
// ERC20.balanceOf(poolEscrow, asset) >= PoolEscrow.holding.total
// 実際のトークン残高 >= 記帳上の合計
invariant_pool_escrow_balance_backing()

// P-PE-3: PoolEscrow Available Accuracy
// PoolEscrow.availableBalanceOf() == holding.total - holding.reserved
// ※ holding.total < holding.reserved の場合は 0 を返す
invariant_pool_escrow_available_accuracy()

// P-PE-4: PoolEscrow Withdrawal Constraint
// withdraw は availableBalance 以下のみ成功
// withdraw(amount) where amount > availableBalance → revert
property_pool_escrow_withdrawal_bounded()

// P-PE-5: PoolEscrow Reserve/Unreserve Symmetry
// reserve(x) → unreserve(x) 後: reserved は元の値に戻る
property_pool_escrow_reserve_symmetry()
```

#### properties/TransferHookProperties.sol（★完全新規）

```solidity
// P-TH-1: Frozen Account Transfer Block
// isFrozen(token, user) == true → transfer from/to user は checkERC20Transfer == false
// ※ endorsed users は除外
property_frozen_blocks_transfer()

// P-TH-2: Non-Member Receive Block (FullRestrictions)
// isMember(token, to) == false && !endorsed(to) → transfer to user は blocked
// ※ 特定フロー（fulfillment等）は例外
property_non_member_receive_blocked()

// P-TH-3: HookData Encoding Consistency
// freeze → FREEZE_BIT set, unfreeze → FREEZE_BIT cleared
// updateMember(validUntil) → upper 64 bits == validUntil
// 両操作は互いの値を破壊しない
property_hookdata_encoding_consistency()

// P-TH-4: Endorsed Bypass
// root.endorsed(user) == true → membership/freeze checks are bypassed
property_endorsed_bypass()

// P-TH-5: Transfer Type Classification Completeness
// 任意の (from, to) ペアは必ず8つのフロータイプのいずれかに分類される
// 分類漏れ（未定義動作）がないことを検証
property_transfer_type_completeness()

// P-TH-6: Auth Transfer Bypass
// authTransferFrom は onERC20AuthTransfer を呼ぶ（checkERC20Transferをスキップ）
// → freeze/membershipに関係なく常に成功
property_auth_transfer_always_succeeds()
```

#### properties/SyncManagerProperties.sol（★完全新規）

```solidity
// P-SM-1: MaxReserve Capacity
// deposit/mint は maxReserve - currentBalance を超過不可
// ※ currentBalance = poolEscrow.availableBalanceOf()
property_sync_deposit_bounded_by_reserve()

// P-SM-2: Price Consistency
// SyncManager.pricePoolPerShare() == ISyncDepositValuation.getPrice() (if set)
// SyncManager.pricePoolPerShare() == spoke.pricePoolPerShare() (if no custom valuation)
property_sync_price_source_consistency()

// P-SM-3: Deposit/Mint Equivalence
// deposit(assets) で得られるshares == mint(convertToShares(assets)) で得られるshares
property_deposit_mint_equivalence()
```

#### properties/VaultRegistryProperties.sol（★完全新規）

```solidity
// P-VR-1: Linked Vault Requirement
// AsyncVault operations require vault to be linked in VaultRegistry
// unlinked vault → operations revert
property_only_linked_vault_operations()

// P-VR-2: Deploy-Link Atomicity
// DeployAndLink は deployVault + linkVault を一度に実行
// 結果: vaultDetails filled && isLinked == true
property_deploy_link_atomicity()

// P-VR-3: No Double Link
// 既にlinkedのvaultに対する再linkはrevert
property_no_double_link()
```

#### properties/RefundEscrowProperties.sol（★完全新規）

```solidity
// P-RE-1: Balance Consistency
// address(refundEscrow).balance >= recorded balance (reentrancy safe)
property_refund_escrow_balance_consistency()

// P-RE-2: Auth-Only Withdrawal
// withdrawFunds は auth modifier で保護
// 非auth呼び出し → revert
property_refund_escrow_auth_withdrawal()
```

### 4.5 TargetFunctions — 新規ターゲット

#### targets/VaultTargets.sol（v3から修正）

```solidity
// v3から継続（全て同様だが内部実装変更あり）
function vault_requestDeposit(uint256 assets) external;
function vault_requestRedeem(uint256 shares) external;
function vault_deposit(uint256 assets) external;
function vault_mint(uint256 shares) external;
function vault_redeem(uint256 shares) external;
function vault_withdraw(uint256 assets) external;

// v3.1修正: cancelDeposit/Redeem が ERC-7887準拠に
function vault_cancelDepositRequest() external;
function vault_cancelRedeemRequest() external;
function vault_claimCancelDepositRequest() external;   // ★新規 (ERC-7887)
function vault_claimCancelRedeemRequest() external;    // ★新規 (ERC-7887)
```

#### targets/PoolEscrowTargets.sol（★完全新規）

```solidity
function escrow_deposit(uint128 amount) external asAdmin {
    amount = uint128(between(uint256(amount), 1, type(uint128).max / 4));
    // asset.mint to test contract first, then approve
    poolEscrow.deposit(scId, asset, 0, amount);
    ghostPoolEscrowTotal[assetId] += amount;
}

function escrow_withdraw(uint128 amount) external asAdmin {
    uint128 available = poolEscrow.availableBalanceOf(scId, asset, 0);
    amount = uint128(between(uint256(amount), 1, available > 0 ? available : 1));
    poolEscrow.withdraw(scId, asset, 0, amount);
    ghostPoolEscrowTotal[assetId] -= amount;
}

function escrow_reserve(uint128 amount) external asAdmin {
    uint128 available = poolEscrow.availableBalanceOf(scId, asset, 0);
    amount = uint128(between(uint256(amount), 1, available > 0 ? available : 1));
    poolEscrow.reserve(scId, asset, 0, amount);
    ghostPoolEscrowReserved[assetId] += amount;
}

function escrow_unreserve(uint128 amount) external asAdmin {
    uint128 reserved = poolEscrow.holding(poolId, scId, asset, 0).reserved;
    amount = uint128(between(uint256(amount), 1, reserved > 0 ? reserved : 1));
    poolEscrow.unreserve(scId, asset, 0, amount);
    ghostPoolEscrowReserved[assetId] -= amount;
}
```

#### targets/TransferHookTargets.sol（★完全新規、旧FullRestrictionsTargets.sol を置換）

```solidity
function hook_freeze(address user) external asAdmin {
    fullRestrictions.freeze(address(shareToken), user);
    ghostIsFrozen[user] = true;
}

function hook_unfreeze(address user) external asAdmin {
    fullRestrictions.unfreeze(address(shareToken), user);
    ghostIsFrozen[user] = false;
}

function hook_updateMember(address user, uint64 validUntil) external asAdmin {
    validUntil = uint64(between(uint256(validUntil), block.timestamp, block.timestamp + 365 days));
    fullRestrictions.updateMember(address(shareToken), user, validUntil);
    ghostValidUntil[user] = validUntil;
}

// Transfer type classification テスト
function hook_checkTransfer(address from, address to, uint256 value) external view {
    bool result = fullRestrictions.checkERC20Transfer(from, to, value, _buildHookData(from, to));
    // 結果を検証（ghostIsFrozen, ghostValidUntilとの整合性）
}
```

#### targets/SyncManagerTargets.sol（★完全新規）

```solidity
function sync_deposit(uint256 assets) external asActor {
    assets = between(assets, 1, syncManager.maxDeposit(syncVault, currentActor));
    syncManager.deposit(syncVault, assets, currentActor, currentActor);
}

function sync_mint(uint256 shares) external asActor {
    shares = between(shares, 1, syncManager.maxMint(syncVault, currentActor));
    syncManager.mint(syncVault, shares, currentActor, currentActor);
}

function sync_setMaxReserve(uint128 maxReserve_) external asAdmin {
    maxReserve_ = uint128(between(uint256(maxReserve_), 0, type(uint128).max));
    syncManager.setMaxReserve(poolId, scId, asset, 0, maxReserve_);
    ghostMaxReserve[assetId] = maxReserve_;
}

function sync_setValuation(address valuation_) external asAdmin {
    syncManager.setValuation(poolId, scId, valuation_);
    ghostSyncValuation = valuation_;
}
```

#### targets/BalanceSheetTargets.sol（★完全新規 — queue操作）

```solidity
function bs_submitQueuedAssets(AssetId assetId_) external asAdmin {
    balanceSheet.submitQueuedAssets(poolId, scId, assetId_, 0, address(this));
}

function bs_submitQueuedShares() external asAdmin {
    balanceSheet.submitQueuedShares(poolId, scId, 0, address(this));
}

function bs_overridePricePoolPerAsset(uint256 priceRaw) external asAdmin {
    D18 price = d18(between(priceRaw, 1e15, 2e18));
    balanceSheet.overridePricePoolPerAsset(poolId, scId, assetId, price);
}

function bs_resetPricePoolPerAsset() external asAdmin {
    balanceSheet.resetPricePoolPerAsset(poolId, scId, assetId);
}

function bs_transferSharesFrom(address from, address to, uint256 amount) external asAdmin {
    balanceSheet.transferSharesFrom(poolId, scId, address(this), from, to, amount);
}
```

### 4.6 SharedStorage.sol 設定フラグ

```solidity
// v3から継続
bool RECON_USE_SINGLE_DEPLOY = true;
bool RECON_TOGGLE_CANARY_TESTS = false;

// v3.1新規
bool RECON_USE_FULL_RESTRICTIONS = true;    // false → FreelyTransferable
bool RECON_USE_ORACLE_VALUATION = false;    // SyncManager valuation切替
bool RECON_ENABLE_SUBSIDY = false;          // AsyncRequestManager subsidy mode
bool RECON_ENABLE_SYNC_VAULT = true;        // SyncManager テスト有効化
uint128 RECON_DEFAULT_MAX_RESERVE = type(uint128).max; // SyncManager maxReserve初期値
```

---

## 5. Suite 3: recon-e2e

### 5.1 ディレクトリ構造

```
protocol/test/integration/recon-end-to-end/
├── Setup.sol                        [v3から大幅修正]
├── BeforeAfter.sol                  [v3から大幅修正]
├── properties/
│   ├── Properties.sol               [v3から大幅修正]
│   ├── HubProperties.sol            [v3から修正]
│   ├── VaultProperties.sol          [v3から修正]
│   ├── EscrowProperties.sol         [v3から修正]
│   ├── BatchRequestProperties.sol   [★新規]
│   ├── NAVProperties.sol            [★新規]
│   ├── PoolEscrowProperties.sol     [★新規]
│   ├── QueueProperties.sol          [★新規]
│   └── CrossSystemProperties.sol    [★新規]
├── targets/
│   ├── AdminTargets.sol             [v3から修正]
│   ├── BalanceSheetTargets.sol      [v3から修正]
│   ├── HubTargets.sol               [v3から修正]
│   ├── ManagerTargets.sol           [v3から修正]
│   ├── RestrictedTransfersTargets.sol [v3から修正]
│   ├── ShareTokenTargets.sol        [v3から修正]
│   ├── SpokeTargets.sol             [v3から修正]
│   ├── ToggleTargets.sol            [v3から修正]
│   ├── VaultTargets.sol             [v3から修正]
│   ├── BatchRequestTargets.sol      [★新規]
│   ├── NAVTargets.sol               [★新規]
│   ├── QueueManagerTargets.sol      [★新規]
│   └── DoomsdayTargets.sol          [v3から修正]
├── managers/
│   ├── ReconPoolManager.sol         [v3から修正]
│   ├── ReconAssetIdManager.sol      [v3から修正]
│   ├── ReconShareClassManager.sol   [v3から修正]
│   ├── ReconShareManager.sol        [v3から修正]
│   ├── ReconVaultManager.sol        [v3から修正]
│   ├── ReconBatchRequestManager.sol [★新規]
│   ├── ReconNAVManager.sol          [★新規]
│   └── ReconQueueManager.sol        [★新規]
├── helpers/
│   ├── SharedStorage.sol            [v3から修正]
│   └── Utils.sol                    [v3から修正]
├── CryticTester.sol
├── CryticToFoundry.t.sol
├── echidna_e2e.yaml
└── medusa.json
```

### 5.2 Setup.sol — デプロイメント設計

#### Real Contracts（Hub + Spoke 両方）

```solidity
// ===== Hub側（全てReal） =====
Root root;
Accounting accounting;
HubRegistry hubRegistry;
Holdings holdings;
Hub hub;
ShareClassManager shareClassManager;
HubHandler hubHandler;
BatchRequestManager batchRequestManager;   // ★新規
NAVManager navManager;                      // ★新規
IdentityValuation identityValuation;
OracleValuation oracleValuation;            // ★新規

// ===== Spoke側（全てReal） =====
Escrow globalEscrow;
PoolEscrow poolEscrow;                      // ★新規
Spoke spoke;
BalanceSheet balanceSheet;
AsyncRequestManager asyncRequestManager;
SyncManager syncManager;                    // ★新規
AsyncVault asyncVault;
ShareToken shareToken;
VaultRegistry vaultRegistry;                // ★新規
RefundEscrow refundEscrow;                  // ★新規
FullRestrictions fullRestrictions;           // BaseTransferHook派生
QueueManager queueManager;                  // ★新規
```

#### Mocked Contracts（最小限 — Gateway層のみ）

```solidity
// v3と同様: メッセージングレイヤーのみモック
MockGateway gateway;
MockMessageDispatcher dispatcher;
MockMessageProcessor processor;
MockMultiAdapter multiAdapter;
```

#### v3からの主な変更点

| v3 | v3.1 | 影響 |
|----|------|------|
| Hub直接のprocessDeposit/Redeem | BatchRequestManager経由 | E2Eフローの全面変更 |
| 単一エスクロー | GlobalEscrow + PoolEscrow | 二重エスクロー管理 |
| FullRestrictions(root) | FullRestrictions(root, spoke, ...) + hookData | Transfer制御の全面変更 |
| — | QueueManager + minDelay | Spokeからの同期にタイミング制約 |
| — | NAVManager | 会計アカウント初期化がマネージャー経由 |
| SyncRequestManager | SyncManager + maxReserve | 同期預入に容量制限 |

### 5.3 managers/ — 新規Reconマネージャー

#### managers/ReconBatchRequestManager.sol（★完全新規）

```solidity
/// @dev E2E fuzzing用のBatchRequestManager操作ラッパー
/// Fuzzerがエポックライフサイクルをシーケンシャルに実行できるようにする
contract ReconBatchRequestManager is SharedStorage {

    function setupBatchRequestManager(PoolId poolId_, uint16 centrifugeId_) internal {
        // hubRegistry.setHubRequestManager(poolId, centrifugeId, batchRequestManager);
    }

    function runDepositEpoch(
        PoolId poolId_,
        ShareClassId scId_,
        AssetId assetId_,
        uint128 approvedAmount,
        D18 approvePrice,
        D18 issuePrice
    ) internal {
        // 1. approveDeposits
        batchRequestManager.approveDeposits(
            poolId_, scId_, assetId_,
            batchRequestManager.nowDepositEpoch(poolId_, scId_, assetId_),
            approvedAmount,
            approvePrice,
            address(this)
        );
        // 2. issueShares
        batchRequestManager.issueShares(
            poolId_, scId_, assetId_,
            batchRequestManager.nowIssueEpoch(poolId_, scId_, assetId_),
            issuePrice,
            0,
            address(this)
        );
    }

    function runRedeemEpoch(
        PoolId poolId_,
        ShareClassId scId_,
        AssetId assetId_,
        uint128 approvedAmount,
        D18 approvePrice,
        D18 revokePrice
    ) internal {
        batchRequestManager.approveRedeems(
            poolId_, scId_, assetId_,
            batchRequestManager.nowRedeemEpoch(poolId_, scId_, assetId_),
            approvedAmount,
            approvePrice
        );
        batchRequestManager.revokeShares(
            poolId_, scId_, assetId_,
            batchRequestManager.nowRevokeEpoch(poolId_, scId_, assetId_),
            revokePrice,
            0,
            address(this)
        );
    }
}
```

#### managers/ReconNAVManager.sol（★完全新規）

```solidity
contract ReconNAVManager is SharedStorage {

    function setupNAV(PoolId poolId_, uint16 centrifugeId_) internal {
        navManager.initializeNetwork(poolId_, centrifugeId_);
    }

    function setupHoldingWithNAV(
        PoolId poolId_,
        ShareClassId scId_,
        AssetId assetId_,
        IValuation valuation_
    ) internal {
        navManager.initializeHolding(poolId_, scId_, assetId_, valuation_);
    }
}
```

#### managers/ReconQueueManager.sol（★完全新規）

```solidity
contract ReconQueueManager is SharedStorage {

    function setupQueueManager(PoolId poolId_, ShareClassId scId_) internal {
        // Set default minDelay and extraGasLimit
        // queueManager.trustedCall(poolId, scId, abi.encode(minDelay, extraGasLimit));
    }

    function executeSync(
        PoolId poolId_,
        ShareClassId scId_,
        AssetId[] memory assetIds_
    ) internal {
        queueManager.sync(poolId_, scId_, assetIds_, address(this));
    }
}
```

### 5.4 Properties — クロスシステムプロパティ

#### properties/CrossSystemProperties.sol（★完全新規）

```solidity
// P-CS-1: Hub-Spoke Deposit Consistency
// Hub側: BatchRequestManager.pendingDeposit
// Spoke側: AsyncRequestManager.pendingDepositRequest per user
// 両者の合計が矛盾しないことを検証
invariant_cross_system_deposit_consistency()

// P-CS-2: Share Issuance Balance
// Hub: shareClassManager.totalIssuance
// Spoke: shareToken.totalSupply()
// ※ クロスチェーン遅延を考慮したupper/lower bound検証
invariant_share_issuance_cross_chain()

// P-CS-3: Escrow Solvency Chain
// GlobalEscrow.balanceOf(asset) >= Σ(user pendingDeposits) + Σ(user cancelledDeposits)
// PoolEscrow.total >= reserved + available deposits
invariant_escrow_solvency_chain()

// P-CS-4: Price Propagation Consistency
// Hub: shareClassManager.pricePoolPerShare
// Spoke: spoke.pricePoolPerShare
// 同一エポック内で一致すること
invariant_price_propagation()

// P-CS-5: BatchRequestManager ↔ AsyncRequestManager整合性
// BRM.notifyDeposit → (via messaging) → ARM.fulfillDepositRequest
// BRM.claimDeposit の結果 == ARM.fulfillDepositRequest で記録される値
invariant_brm_arm_fulfillment_consistency()

// P-CS-6: Queue Sync Completeness
// QueueManager.sync 後: 全 assetId の queuedAssets.delta == 0
// queuedShares.delta == 0 (全て submitted)
property_queue_sync_completeness()

// P-CS-7: NAV Accounting Consistency
// navManager.netAssetValue == Σ(holdings.value for all initialized assets) + equity adjustments
property_nav_accounting_consistency()
```

#### properties/BatchRequestProperties.sol（★完全新規 — E2E版）

```solidity
// P-BRM-E2E-1: Full Deposit Cycle Conservation
// requestDeposit(X assets) → approve → issue → claim
// ユーザーが受け取る shares の価値 <= X assets (プロトコル有利丸め)
property_deposit_cycle_no_value_creation()

// P-BRM-E2E-2: Full Redeem Cycle Conservation
// requestRedeem(Y shares) → approve → revoke → claim
// ユーザーが受け取る assets の価値 <= Y shares の価値 (プロトコル有利丸め)
property_redeem_cycle_no_value_creation()

// P-BRM-E2E-3: Cancel Roundtrip
// requestDeposit(X) → cancelDepositRequest → claimCancelDeposit
// ユーザーは X assets を回収可能（丸め誤差は最大1 wei）
property_cancel_deposit_roundtrip()
```

### 5.5 OpType enum（E2E版）

```solidity
enum OpType {
    GENERIC,
    // Admin operations
    ADMIN,
    // Hub operations
    HUB_CREATE_POOL,
    HUB_ADD_SHARE_CLASS,
    HUB_INITIALIZE_HOLDING,
    // BatchRequestManager operations
    BRM_REQUEST_DEPOSIT,
    BRM_REQUEST_REDEEM,
    BRM_CANCEL_DEPOSIT,
    BRM_CANCEL_REDEEM,
    BRM_APPROVE_DEPOSITS,
    BRM_ISSUE_SHARES,
    BRM_APPROVE_REDEEMS,
    BRM_REVOKE_SHARES,
    BRM_CLAIM_DEPOSIT,
    BRM_CLAIM_REDEEM,
    BRM_FORCE_CANCEL,
    // Vault operations
    VAULT_REQUEST_DEPOSIT,
    VAULT_REQUEST_REDEEM,
    VAULT_DEPOSIT,
    VAULT_MINT,
    VAULT_REDEEM,
    VAULT_WITHDRAW,
    // BalanceSheet operations
    BS_SUBMIT_QUEUED_ASSETS,
    BS_SUBMIT_QUEUED_SHARES,
    // NAV operations
    NAV_UPDATE,
    NAV_CLOSE_GAIN_LOSS,
    // Queue operations
    QUEUE_SYNC,
    // Transfer operations
    TRANSFER,
    // Toggle
    TOGGLE
}
```

---

## 6. Suite 4: recon-aggregator

### 6.1 ディレクトリ構造

```
protocol/test/vaults/fuzzing/recon-aggregator/
├── Setup.sol                        [v3から大幅修正]
├── BeforeAfter.sol                  [v3から修正]
├── Properties.sol                   [v3から修正+新規追加]
├── TargetFunctions.sol              [v3から修正]
├── targets/
│   ├── BiasedTargetFunctions.sol    [v3 WIP → 完全実装]
│   └── BatchTargetFunctions.sol     [★新規]
├── CryticTester.sol
├── CryticToFoundry.t.sol
├── echidna_aggregator.yaml
└── medusa.json
```

### 6.2 Setup.sol — デプロイメント設計

#### Real Contracts

```solidity
// v3から継続
Gateway gateway;
MockAdapter[] adapters;          // 2+ adapters

// v3.1新規
GasService gasService;           // ★新規 (per-message gas limits)
Root root;
```

#### v3からの変更点

```solidity
function setup() internal override {
    root = new Root(address(this));

    // v3.1: GasService deploy
    gasService = new GasService(address(this));
    // 27メッセージタイプのガスリミット設定
    for (uint8 i = 1; i <= 26; i++) {
        gasService.setGasLimit(i, 100_000); // デフォルト値
    }

    // Gateway (v3.1: root, gasService追加)
    gateway = new Gateway(root, gasService, address(this));

    // Adapters (v3と同様: 2アダプター)
    for (uint i = 0; i < RECON_ADAPTERS; i++) {
        adapters.push(new MockAdapter());
    }

    // Adapter設定 (v3.1: GLOBAL_POOL)
    IAdapter[] memory adapterList = new IAdapter[](RECON_ADAPTERS);
    for (uint i = 0; i < RECON_ADAPTERS; i++) {
        adapterList[i] = IAdapter(address(adapters[i]));
    }
    gateway.setAdapters(
        centrifugeId,
        PoolId.wrap(0),  // GLOBAL_POOL
        adapterList,
        new bytes32[](RECON_ADAPTERS),
        RECON_ADAPTERS,  // threshold = adapter count (unanimous quorum)
        0                // recoveryIndex
    );

    // Permission
    gateway.rely(address(this)); // test contract as handler
}
```

### 6.3 Ghost変数

```solidity
// v3から継続
mapping(bytes32 => uint256) messageSentCount;
mapping(bytes32 => uint256) proofSentCount;
mapping(bytes32 => uint256) messageReceivedCount;
mapping(bytes32 => uint256) messageRecoveredCount;

// v3.1新規
mapping(bytes32 => uint256) ghostFailedMessageCount;    // Gateway.failedMessages
mapping(bytes32 => uint256) ghostUnderpaidCount;        // Gateway.underpaid
uint256 ghostBatchMessageCount;                          // バッチ内メッセージ数
uint256 ghostTotalGasPaid;                               // 累計ガス支払い
uint256 ghostTotalGasRefunded;                           // 累計ガス返金
bool ghostIsBatching;                                    // バッチモード中か
```

### 6.4 Properties — 不変条件設計

#### v3から継続（修正あり）

```solidity
// P-AGG-1: Message No-Replay (v3と同様)
// messageReceivedCount <= messageSentCount + messageRecoveredCount
// ※ v3.1ではfailedMessages のretryも考慮
invariant_noMessageReplay()
```

#### v3.1新規プロパティ

```solidity
// P-AGG-2: Batch Atomicity
// withBatch() 内の全メッセージが同一トランザクションで送信される
// バッチ途中でrevertした場合、全メッセージがロールバック
property_batch_atomicity()

// P-AGG-3: Gas Payment Accuracy
// Σ(msg.value per send) >= Σ(gasService.estimateGas per message)
// 余剰は RefundEscrow に返金
property_gas_payment_accuracy()

// P-AGG-4: Failed Message Retry
// failedMessages[hash] > 0 のメッセージは retry() で再実行可能
// retry後 failedMessages[hash] が減少
property_failed_message_retry()

// P-AGG-5: Unpaid Mode Safety
// unpaidMode == true の間のみ underpaid メッセージを蓄積可能
// unpaidMode == false 時は underpaid 蓄積不可
property_unpaid_mode_safety()

// P-AGG-6: Pool-Specific Adapter Isolation
// pool A のアダプター設定変更は pool B のメッセージ処理に影響しない
property_pool_adapter_isolation()

// P-AGG-7: Quorum Enforcement
// メッセージ受信は threshold 数以上のアダプターからの確認を要求
// threshold未満の確認では execute されない
property_quorum_enforcement()

// P-AGG-8: Outgoing Block Enforcement
// isOutgoingBlocked[centrifugeId][poolId] == true の場合、send revert
property_outgoing_block_enforcement()
```

### 6.5 TargetFunctions

#### targets/BiasedTargetFunctions.sol（v3 WIP → 完全実装）

```solidity
// v3では全てコメントアウトだったものを完全実装

function biased_registerNewMessage(bytes memory payload)
    external updateGhosts
{
    bytes32 messageHash = keccak256(payload);
    messageSentCount[messageHash]++;
    // adapter[0] にメッセージ送信をシミュレート
}

function biased_sendMessage(uint256 adapterIndex, bytes memory payload)
    external updateGhosts
{
    adapterIndex = between(adapterIndex, 0, adapters.length - 1);
    bytes32 messageHash = keccak256(payload);
    // adapter[adapterIndex] 経由で gateway.handle() 呼び出し
}

function biased_sendProof(uint256 adapterIndex, bytes memory payload)
    external updateGhosts
{
    adapterIndex = between(adapterIndex, 0, adapters.length - 1);
    bytes32 messageHash = keccak256(payload);
    proofSentCount[messageHash]++;
    // proof送信
}

function biased_recoverMessage(bytes memory payload)
    external updateGhosts
{
    bytes32 messageHash = keccak256(payload);
    messageRecoveredCount[messageHash]++;
}

function biased_executeMessageRecovery(bytes memory payload)
    external updateGhosts
{
    bytes32 messageHash = keccak256(payload);
    // recovery実行
}

function biased_disputeMessageRecovery(bytes memory payload)
    external updateGhosts
{
    // recovery dispute
}
```

#### targets/BatchTargetFunctions.sol（★完全新規）

```solidity
function batch_withBatch(bytes[] memory messages)
    external payable updateGhosts
{
    // withBatch() を使用した複数メッセージ送信
    gateway.withBatch{value: msg.value}(
        abi.encodeWithSelector(this.batchCallback.selector, messages),
        address(this)
    );
    ghostBatchMessageCount += messages.length;
}

function batch_send(bytes memory message, uint256 gasLimit)
    external payable updateGhosts
{
    gateway.send{value: msg.value}(message, gasLimit);
}

function batch_setUnpaidMode(bool enabled)
    external updateGhosts
{
    gateway.setUnpaidMode(enabled);
    ghostIsBatching = enabled;
}

function batch_repay(uint16 centrifugeId_, bytes32 messageHash)
    external payable updateGhosts
{
    gateway.repay{value: msg.value}(centrifugeId_, messageHash);
}

function batch_retryMessage(uint16 centrifugeId_, bytes memory message)
    external updateGhosts
{
    gateway.retry(centrifugeId_, message);
}

function batch_blockOutgoing(uint16 centrifugeId_, PoolId poolId_, bool isBlocked)
    external updateGhosts
{
    gateway.blockOutgoing(centrifugeId_, poolId_, isBlocked);
}

function batch_setGasLimit(uint8 messageType, uint256 gasLimit)
    external updateGhosts
{
    gasService.setGasLimit(messageType, gasLimit);
}
```

---

## 7. Echidna/Medusa設定

### 7.1 echidna_hub.yaml（v3から微修正）

```yaml
testMode: assertion
seqLen: 200
testLimit: 100000000
corpusDir: corpus-hub
deployer: "0x10000"
sender: ["0x20000", "0x30000", "0x40000"]
cryticArgs:
  - --compile-force-framework
  - foundry
# v3.1追加: BatchRequestManager のライブラリデプロイ
deployContracts:
  - ["0x50000", "PricingLib"]
  - ["0x50001", "MathLib"]
  - ["0x50002", "TransientBytesLib"]    # ★新規
  - ["0x50003", "TransientJournal"]     # ★新規
  - ["0x50004", "RequestMessageLib"]    # ★新規
```

### 7.2 echidna_core.yaml（v3から微修正）

```yaml
testMode: assertion
seqLen: 200
testLimit: 100000000
corpusDir: corpus-core
deployer: "0x10000"
sender: ["0x20000", "0x30000", "0x40000"]
cryticArgs:
  - --compile-force-framework
  - foundry
deployContracts:
  - ["0x50000", "PricingLib"]
  - ["0x50001", "MathLib"]
  - ["0x50002", "SafeTransferLib"]
  - ["0x50003", "UpdateRestrictionMessageLib"]  # ★新規 (BaseTransferHook用)
```

### 7.3 echidna_e2e.yaml

```yaml
testMode: assertion
seqLen: 300         # v3の200から増加（BatchRequestManagerのフルサイクルに対応）
testLimit: 100000000
corpusDir: corpus-e2e
deployer: "0x10000"
sender: ["0x20000", "0x30000", "0x40000"]
cryticArgs:
  - --compile-force-framework
  - foundry
deployContracts:
  - ["0x50000", "PricingLib"]
  - ["0x50001", "MathLib"]
  - ["0x50002", "TransientBytesLib"]
  - ["0x50003", "TransientJournal"]
  - ["0x50004", "RequestMessageLib"]
  - ["0x50005", "RequestCallbackMessageLib"]
  - ["0x50006", "SafeTransferLib"]
  - ["0x50007", "UpdateRestrictionMessageLib"]
```

### 7.4 echidna_aggregator.yaml（v3から修正）

```yaml
testMode: assertion
seqLen: 100         # v3の50から増加（バッチ操作対応）
testLimit: 100000000
corpusDir: corpus-aggregator
deployer: "0x10000"
sender: ["0x20000", "0x30000", "0x40000"]
cryticArgs:
  - --compile-force-framework
  - foundry
deployContracts:
  - ["0x50000", "TransientBytesLib"]    # ★新規
```

---

## 8. 実装優先度とロードマップ

### 8.1 優先度マトリクス

| 優先度 | スイート | コンポーネント | 理由 |
|-------|---------|--------------|------|
| **P0 (Critical)** | recon-hub | BatchRequestManager ターゲット + プロパティ | 977行の最大新規追加。エポック処理の正確性は Critical/High リスク |
| **P0 (Critical)** | recon-core | PoolEscrow プロパティ | エスクロー不整合はファンドロスに直結 |
| **P0 (Critical)** | recon-e2e | BRM ↔ ARM クロスシステムプロパティ | Hub-Spoke間の整合性検証 |
| **P1 (High)** | recon-hub | NAVManager ターゲット + プロパティ | NAV操作 → 価格操作リスク |
| **P1 (High)** | recon-core | TransferHook プロパティ | 凍結/メンバーシップバイパス → Medium+リスク |
| **P1 (High)** | recon-hub | Accounting EIP-1153 プロパティ | トランジェントストレージの安全性 |
| **P1 (High)** | recon-core | AsyncVault ERC-7887 ターゲット | cancel/claim新フロー |
| **P2 (Medium)** | recon-core | SyncManager プロパティ | maxReserve容量制限の正確性 |
| **P2 (Medium)** | recon-core | VaultRegistry プロパティ | マルチマネージャーVault整合性 |
| **P2 (Medium)** | recon-aggregator | Batch送信プロパティ | withBatch()のアトミシティ |
| **P2 (Medium)** | recon-aggregator | BiasedTargets完全実装 | v3 WIPの完成 |
| **P3 (Low)** | recon-core | RefundEscrow プロパティ | Sherlock severity override: Medium max |
| **P3 (Low)** | recon-aggregator | GasService gas limit プロパティ | ガスリミット設定の正確性 |

### 8.2 実装順序

```
Phase 1: Hub Suite Foundation (推定: 最初に着手)
├── 1a. Setup.sol: BatchRequestManager + HubHandler デプロイ
├── 1b. BatchRequestTargets.sol: 全ターゲット実装
├── 1c. Properties.sol: P-BRM-1 ~ P-BRM-9 実装
├── 1d. BeforeAfter.sol: ghost変数追加
└── 1e. echidna_hub.yaml 更新 + 初回実行・バグ確認

Phase 2: Core Suite Foundation (Hub完了後)
├── 2a. Setup.sol: PoolEscrow + VaultRegistry + SyncManager デプロイ
├── 2b. PoolEscrowTargets.sol + TransferHookTargets.sol 実装
├── 2c. PoolEscrowProperties.sol + TransferHookProperties.sol 実装
├── 2d. VaultTargets.sol 更新 (ERC-7887対応)
└── 2e. echidna_core.yaml 更新 + 実行

Phase 3: E2E Integration (Hub + Core完了後)
├── 3a. Setup.sol: Hub + Spoke 全Real contracts デプロイ
├── 3b. ReconBatchRequestManager + ReconNAVManager + ReconQueueManager
├── 3c. CrossSystemProperties.sol: P-CS-1 ~ P-CS-7 実装
├── 3d. BatchRequestTargets.sol (E2E版)
└── 3e. echidna_e2e.yaml 更新 + 実行

Phase 4: Aggregator Completion (並行可能)
├── 4a. Setup.sol: Gateway + GasService デプロイ
├── 4b. BiasedTargetFunctions.sol 完全実装 (v3 WIP → 完成)
├── 4c. BatchTargetFunctions.sol 新規実装
├── 4d. Properties.sol: P-AGG-2 ~ P-AGG-8 実装
└── 4e. echidna_aggregator.yaml 更新 + 実行

Phase 5: Doomsday & Optimization
├── 5a. DoomsdayTargets: 全スイートの differential/rounding 検証
├── 5b. Shortcut functions: フルサイクルショートカット最適化
├── 5c. Canary tests: 既知の問題を意図的に再現するテスト
└── 5d. Coverage analysis + 追加ターゲット
```

### 8.3 Sherlock監査との対応

| Sherlock Known Issue / Severity Override | Fuzzing対応 |
|----------------------------------------|-------------|
| DOS = permanent lock → High only | P-BRM-7 Claim完全性、P-PE-4 Withdrawal Constraint |
| Hook bypass → Medium max | P-TH-1~6 TransferHook プロパティ群 |
| RefundEscrow native → Medium max | P-RE-1~2 RefundEscrow プロパティ（P3優先度） |
| Pool managers trusted within own pool | ManagerTargets: isManager modifier 検証 |
| Pool managers manipulating other pools | P-CS-6 Pool adapter isolation, cross-pool mutation guards |
| ERC-7540 compliance | P-7540-1~7 AsyncVaultProperties |
| Rounding always in protocol's favor | DoomsdayTargets: rounding differential |

### 8.4 成功基準

| メトリクス | 目標値 |
|-----------|-------|
| Echidna assertion violations | 0（全プロパティがパス） |
| Medusa assertion violations | 0 |
| seqLen カバレッジ | 200+ calls per sequence |
| testLimit | 100M+ per suite |
| Hub Suite プロパティ数 | 20+ (v3: 14 → v3.1: 20+) |
| Core Suite プロパティ数 | 40+ (v3: 30 → v3.1: 40+) |
| E2E Suite プロパティ数 | 50+ |
| Aggregator Suite プロパティ数 | 10+ (v3: 1active → v3.1: 10+) |
| 発見した脆弱性 | High/Medium 1件以上が目標 |

---

## 付録A: v3→v3.1 プロパティ対応表

| v3 プロパティ | v3.1 対応 | 変更内容 |
|-------------|----------|---------|
| property_accounting_soundness | property_accounting_balance_at_lock | EIP-1153対応 |
| property_epoch_monotonicity | property_epoch_monotonicity (4-epoch版) | deposit/issue/redeem/revoke 4分割 |
| property_pending_approved_consistency | invariant_pending_deposit_consistency + invariant_pending_redeem_consistency | BRM準拠に分割 |
| property_user_mutation_guard | property_queued_order_lifecycle | キュー操作を含む |
| property_eligible_redemption | property_claim_completeness | BRM claim対応 |
| E-1 ~ E-4 (escrow) | E-1 ~ E-4 + P-PE-1 ~ P-PE-5 | PoolEscrow追加 |
| ERC-7540 properties | ERC-7540 + ERC-7887 properties | cancelDeposit拡張 |
| TT-1, TT-3 (share token) | P-TH-1 ~ P-TH-6 | BaseTransferHook対応 |
| invariant_noMessageReplay | invariant_noMessageReplay + P-AGG-2 ~ P-AGG-8 | バッチ/ガス追加 |

## 付録B: Mock コントラクト仕様

### MockGateway (全スイート共通)

```solidity
contract MockGateway {
    // send: メッセージを記録するだけ（実際のクロスチェーン送信はしない）
    bytes[] public sentMessages;

    function send(bytes calldata message, uint256 gasLimit) external payable {
        sentMessages.push(message);
    }

    // withBatch: コールバックを即座に実行
    function withBatch(bytes calldata callback, address refund) external payable {
        (bool success,) = msg.sender.call(callback);
        require(success);
        // 余剰ETHをrefundに返金
    }

    // handle: メッセージを処理対象に転送
    function handle(uint16 centrifugeId, bytes calldata message) external {
        // processor.handle() を呼び出し
    }
}
```

### MockSpoke (Hub Suite用)

```solidity
contract MockSpoke {
    // requestCallback: コールバック受信を記録
    struct Callback {
        PoolId poolId;
        ShareClassId scId;
        AssetId assetId;
        bytes payload;
    }
    Callback[] public receivedCallbacks;

    function requestCallback(PoolId poolId, ShareClassId scId, AssetId assetId, bytes calldata payload) external {
        receivedCallbacks.push(Callback(poolId, scId, assetId, payload));
    }
}
```

### MockHub (Core Suite用)

```solidity
contract MockHub {
    // v3.1: updateAccountingAmount/Value をシミュレート
    // 実際の会計処理は行わず、呼び出しを記録

    // v3.1: IHubRequestManagerCallback として BatchRequestManager から呼ばれる
    function executeRequest(PoolId, ShareClassId, uint256, bytes calldata) external {}
    function requestCallback(PoolId, ShareClassId, AssetId, bytes calldata, uint128, address) external payable {}
}
```
