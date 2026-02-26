# Centrifuge Protocol v3.1 - Audit Memo

## Phase 3 (recon-e2e) E2E Fuzzing Findings

### Finding 1: PoolEscrow.reserve() Missing Upper Bound Check [HIGH]

**Status: New Finding - Submit to Sherlock**

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

Same call chain upstream. Fix in Finding 1 resolves both.

## Sherlock Submission Summary

| Finding | Severity | Verdict | Reason |
|---------|----------|---------|--------|
| 1 PoolEscrow.reserve bounds | High | Submit | Undiscovered in 19 audits, fund lock risk |
| 2 totalAssets stale price | Info | Do NOT submit | README known issue |
| 3 revokedShares bounds | High | Merge with 1 | Same root cause |

## Test Results
- Foundry: 15/15 pass
- Echidna: 148/150 (2 = Finding 1: P-PE-1, P-PE-3)
- Medusa: 127/128 (1 = Finding 2: totalAssets solvency)
