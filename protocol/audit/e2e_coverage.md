# E2E Medusa Coverage Report

**Corpus**: 851 sequences | **Failures**: 0/all | **Overall (protocol src)**: 49.5% (2,124/4,289 lines)

## Key Achievement

**全6ライフサイクルパスが完全カバー** — Hub↔Spoke 境界を横断する全主要フローが実行確認済み。

| Lifecycle Path | Status | Steps |
|---|---|---|
| Deposit (full cycle) | ✅ 10/10 | request → approve → issue → notify → fulfill → claim |
| Redeem (full cycle) | ✅ 10/10 | request → approve → revoke → reserve → notify → fulfill → claim |
| Cancel Deposit | ✅ 4/4 | cancel → hub process → force cancel → claim refund |
| Cancel Redeem | ✅ 4/4 | cancel → hub process → force cancel → claim shares |
| Price Propagation | ✅ 8/8 | hub updateSharePrice → spoke read → balanceSheet override |
| NAV & Accounting | ✅ 9/9 | initNetwork → initHolding → updateValue → closeGainLoss → sync |

## Per-Category Coverage

| Category | Hit | Total | Coverage | Files |
|---|---|---|---|---|
| Spoke (Core) | 305 | 473 | **64.5%** | 9 |
| Misc / Libraries | 256 | 410 | **62.4%** | 20 |
| Vaults | 624 | 1,178 | **53.0%** | 13 |
| Messaging | 458 | 929 | **49.3%** | 9 |
| Hub (Core) | 352 | 817 | **43.1%** | 16 |
| Other | 111 | 394 | **28.2%** | 20 |

## Per-Contract Coverage

### Hub Side (43.1%)

| Contract | Hit/Total | Coverage |
|---|---|---|
| IdentityValuation.sol | 6/7 | 86% |
| OracleValuation.sol | 17/20 | 85% |
| BatchRequestManager.sol | 326/385 | **85%** |
| ShareClassManager.sol | 43/55 | 78% |
| QueueManager.sol | 21/32 | 66% |
| HubRegistry.sol | 30/48 | 62% |
| NAVManager.sol | 68/111 | 61% |
| Holdings.sol | 46/83 | 55% |
| Hub.sol | 91/185 | 49% |
| HubHandler.sol | 12/34 | 35% |
| Accounting.sol | 18/56 | 32% |

### Spoke Side (64.5%)

| Contract | Hit/Total | Coverage |
|---|---|---|
| PoolEscrowFactory.sol | 19/22 | 86% |
| ShareToken.sol | 40/48 | 83% |
| VaultRegistry.sol | 35/51 | 69% |
| BalanceSheet.sol | 87/130 | 67% |
| TokenFactory.sol | 14/23 | 61% |
| Spoke.sol | 91/163 | 56% |
| PoolEscrow.sol | 13/25 | 52% |

### Vaults (53.0%)

| Contract | Hit/Total | Coverage |
|---|---|---|
| RequestCallbackMessageLib.sol | 32/33 | **97%** |
| AsyncVaultFactory.sol | 15/17 | 88% |
| AsyncRequestManager.sol | 166/308 | 54% |
| AsyncVault.sol | 27/45 | 60% |
| BaseVaults.sol | 43/130 | 33% |

### Messaging (49.3%)

| Contract | Hit/Total | Coverage |
|---|---|---|
| Gateway.sol | 84/128 | 66% |
| MultiAdapter.sol | 56/86 | 65% |
| GasService.sol | 58/92 | 63% |
| MessageProcessor.sol | 78/166 | 47% |
| MessageLib.sol | 125/270 | 46% |

## E2E vs Core-Only Coverage Comparison

### E2E が Core を大幅に上回るコントラクト

| Contract | Core | E2E | Delta | Reason |
|---|---|---|---|---|
| BatchRequestManager | 0% | **85%** | +85pp | Hub-side epoch lifecycle (E2E-exclusive) |
| Hub.sol | 0% | **49%** | +49pp | Pool/share management (E2E-exclusive) |
| NAVManager | 0% | **61%** | +61pp | NAV accounting (E2E-exclusive) |
| Holdings | 0% | **55%** | +55pp | Holding initialization (E2E-exclusive) |
| Gateway | 0% | **66%** | +66pp | Message routing (E2E-exclusive) |
| MultiAdapter | 0% | **65%** | +65pp | Adapter quorum (E2E-exclusive) |
| ShareClassManager | 0% | **78%** | +78pp | Share class management (E2E-exclusive) |
| QueueManager | 0% | **66%** | +66pp | Queue sync (E2E-exclusive) |
| TransientArrayLib | 5% | **100%** | +95pp | Batch message processing |
| TransientBytesLib | 4% | **100%** | +96pp | Batch message encoding |

### Core が E2E を上回るコントラクト

| Contract | Core | E2E | Delta | Reason |
|---|---|---|---|---|
| Root.sol | 92% | 27% | -65pp | Admin/pause operations |
| PoolEscrow.sol | 100% | 52% | -48pp | Direct reserve/unreserve |
| AsyncVault.sol | 100% | 60% | -40pp | All vault entry points |
| SyncManager.sol | 85% | 4% | -81pp | Not deployed in E2E |
| PricingLib.sol | 85% | 20% | -65pp | More diverse price paths |
| AsyncRequestManager | 88% | 54% | -34pp | More claim path diversity |

### Combined Coverage

| Suite | Lines | Hit | Coverage |
|---|---|---|---|
| Core-only | 4,289 | 1,356 | 31.6% |
| E2E-only | 4,289 | 2,124 | 49.5% |
| **Core ∪ E2E** | **4,289** | **2,663** | **62.1%** |

E2E は Core にない **1,307 lines** のユニークカバレッジを追加。

## E2E-Exclusive Coverage（Core では不可能なパス）

E2E スイートでのみ検証可能な cross-system パス:

1. **BRM epoch lifecycle**: requestDeposit → approveDeposits → issueShares → notifyDeposit（Hub内部の完全なエポック処理）
2. **Cross-chain message routing**: Gateway → MultiAdapter → MessageProcessor（実際のメッセージシリアライゼーション）
3. **Hub↔Spoke state reconciliation**: shares issuance on Spoke synced with Hub totalIssuance
4. **NAV accounting integration**: initializeHolding → updateHoldingValue → closeGainLoss → netAssetValue
5. **PoolEscrow.reserve via revokedShares**: BRM → Gateway → ARM.revokedShares → BalanceSheet.reserve（間接パス）
6. **Cancel flow across boundary**: ARM.cancelDeposit → Gateway → BRM.cancelDeposit → BRM.forceCancelDeposit

## Structurally Unreachable (E2E)

| Function | Reason |
|---|---|
| SyncManager.* | Not deployed in E2E (async-only) |
| AxelarAdapter/LayerZero/Wormhole | Mocked via SimplifiedLocalAdapter |
| VaultRouter.* | Not used in E2E setup |
| OpsGuardian/ProtocolGuardian | Admin contracts, out of scope |
| SimplePriceManager/MerkleProofManager | Not deployed |
| Spoke.crosschainTransferShares | centrifugeId mismatch in single-chain |

## Properties Verified (0 failures)

All E2E properties pass — no assertion violations:

- **P-CS-1**: Hub-Spoke deposit consistency
- **P-CS-2**: Share issuance balance (with queuedShares delta)
- **P-CS-3a**: Global escrow solvency
- **P-CS-4**: Price propagation consistency
- **P-CS-5**: BRM epoch monotonicity
- **P-CS-6**: Share token conservation
- **P-CS-7**: Queue sync completeness
- **P-CS-8**: NAV accounting consistency
- **P-CS-9**: Accounting equation (asset + loss == equity + gain)
- **P-E-1/2**: Global escrow asset/share solvency
- **P-PE-2**: PoolEscrow ERC20 balance >= total
- **P-PE-3**: PoolEscrow available balance consistency
