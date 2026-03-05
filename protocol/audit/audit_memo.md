# Centrifuge Protocol v3.1 - Audit Memo

## Phase 3 (recon-e2e) E2E Fuzzing Findings

### Finding 1: PoolEscrow.reserve() Missing Upper Bound Check [Info-Protocol test it]

PoolEscrow.reserve() does not validate reserved + value <= total.
withdraw() correctly checks total >= reserved, but reserve() does not.
Hub-side revokedShares() callback can cause reserved > total, locking funds.

Vulnerable code: src/core/spoke/PoolEscrow.sol L46-51
Compare with: withdraw() L33-38 (has the check)

Call chain:
Hub batchRequestManager.revokeShares()
-> message -> Spoke
-> AsyncRequestManager.revokedShares() L280-296
-> balanceSheet.reserve() L134-140
-> poolEscrow.reserve() - NO total bound check

Attack: If assetAmount > total, reserve succeeds, availableBalanceOf underflows to 0,
all subsequent withdraw() calls fail. Funds locked.

Known issue analysis:

- README.md known issues (L68-92): NOT mentioned
- Recon 2025-04 audit (v3): NOT found (M-01 is different)
- Electisec 2025-10 audit (v3.1): NOT found (PoolEscrow in scope)
- recon-core P-PE-1: exists but target clamps, so isolated testing cannot trigger

Conclusion: Undiscovered across 19 prior audits. Cross-system bug only found via E2E fuzzing.

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
