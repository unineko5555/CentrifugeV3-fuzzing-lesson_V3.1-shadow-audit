# Centrifuge Protocol v3.1 -- Project Overview

## Purpose
Centrifuge is an open-source, decentralized protocol for **tokenizing and distributing real-world assets (RWA)** across multiple blockchain networks. It provides infrastructure for creating customizable asset management pools with cross-chain deployment, onchain double-entry bookkeeping, and standards-based DeFi composability.

## Architecture: Hub-and-Spoke
- **Hub Chain** (Centrifuge mainnet, centrifugeId=1): Central orchestration, pool logic, accounting, share class management
- **Spoke Chains** (Ethereum, Base, Arbitrum, Avalanche, BNB, Plume): User-facing vaults, share tokens, escrows, asset custody

## Core Data Model
```
Pool (PoolId = uint64: centrifugeId[16bit] + localPoolId[48bit])
  ├── Currency (AssetId) -- denominating asset
  ├── ShareClass (ShareClassId = bytes16: PoolId[64bit] + index[32bit] + padding)
  │     ├── Holding (AssetId) → Valuation, Accounting accounts
  │     └── Holdings can be assets or liabilities
  ├── Accounting Accounts (double-entry bookkeeping)
  └── Managers (address → bool)
```

## Key Contract Modules

### Hub (Central Chain)
- **Hub.sol**: Main orchestrator/facade for all pool management operations
- **HubHandler.sol**: Processes incoming cross-chain messages from spokes
- **ShareClassManager.sol**: Share class creation, pricing, per-network issuance tracking
- **Accounting.sol**: Full double-entry bookkeeping with unlock/lock invariant (debits == credits)
- **Holdings.sol**: Asset amount/value ledger, valuations, snapshot state for cross-chain sync
- **HubRegistry.sol**: Registry for pools, assets, managers, and dependencies

### Spoke (EVM Chains)
- **Spoke.sol**: Local registry, price feeds, cross-chain share transfers, asset registration
- **ShareToken.sol**: ERC20 + ERC1404 with transfer hook system, compact balance storage (uint128 + bytes16 hookData)
- **BalanceSheet.sol**: Issue/revoke shares, deposit/withdraw assets, queue cross-chain state updates
- **VaultRegistry.sol**: Vault deployment, linking/unlinking via factories
- **PoolEscrow.sol**: Per-pool asset custody with deposit/withdraw/reserve operations

### Vaults (User-Facing)
- **AsyncVault.sol**: Full ERC-7540 asynchronous deposit/redeem (request → fulfill → claim)
- **SyncDepositVault.sol**: ERC-4626 sync deposit + ERC-7540 async redeem
- **AsyncRequestManager.sol**: Spoke-side async request/claim lifecycle
- **BatchRequestManager.sol**: Hub-side epoch-based batching of deposit/redeem requests
- **SyncManager.sol**: Spoke-side synchronous deposit processing
- **VaultRouter.sol**: User-facing aggregator for simplified EOA interactions
- **RefundEscrow.sol**: Per-pool ETH escrow for cross-chain gas subsidies

### Messaging
- **Gateway.sol**: Central routing, batching (EIP-1153 transient storage), failed msg retry, pause
- **MessageDispatcher.sol**: Serialization + local vs. remote routing for outbound messages
- **MessageProcessor.sol**: Deserialization + handler dispatch for inbound messages
- **MultiAdapter.sol**: N-of-M quorum-based multi-bridge consensus, session-based vote invalidation
- **GasService.sol**: Per-message-type gas limit estimation (immutable)
- **MessageLib.sol**: 26 message types with packed encoding, pool ID extraction, source chain validation

### Adapters
- **AxelarAdapter.sol**: Axelar bridge integration (RECEIVE_COST=26k)
- **LayerZeroAdapter.sol**: LayerZero V2 integration (RECEIVE_COST=4k)
- **WormholeAdapter.sol**: Wormhole Relayer integration (RECEIVE_COST=70k)
- **RecoveryAdapter.sol**: Manual message injection for governance recovery

### Admin
- **Root.sol**: Apex of permission hierarchy, timelocked `scheduleRely` (up to 4 weeks)
- **ProtocolGuardian.sol**: Safe multisig interface - pause/unpause, upgrades, adapter reconfig
- **OpsGuardian.sol**: Operations Safe - one-time adapter init, pool creation
- **TokenRecoverer.sol**: Atomic grant-execute-revoke token recovery

### Hooks (Transfer Restrictions)
- **BaseTransferHook.sol**: Abstract base with memberlist, freeze, cross-chain message handling
- **FreelyTransferable.sol**: Freeze + memberlist for vault ops only
- **FreezeOnly.sol**: Minimal - only freeze check
- **FullRestrictions.sol**: Maximum - memberlist for all transfers
- **RedemptionRestrictions.sol**: Memberlist only for redeem requests

### Managers
- **NAVManager.sol**: Hub-side double-entry NAV accounting per network
- **SimplePriceManager.sol**: Single-share-class price calculation from NAV/issuance
- **QueueManager.sol**: Spoke-side batched queue submission with anti-spam timing
- **MerkleProofManager.sol**: Granular permissioned operations via merkle proof policies
- **OnOfframpManager.sol**: ERC20 on/off ramping with relayer-controlled withdrawals

### Valuations
- **IdentityValuation.sol**: Always 1:1 (stablecoins, pegged assets)
- **OracleValuation.sol**: Trusted price feeder with immediate revaluation

### Misc
- **Auth.sol**: MakerDAO ward pattern (wards mapping, rely/deny)
- **D18.sol**: Fixed-point decimal type (uint128, 18 decimals)
- **PricingLib.sol**: All price-based amount conversions (asset↔share↔pool)
- **ERC20.sol**: Standard ERC20 + EIP-2612 permit with virtual balance storage
- **Escrow.sol**: Base custody for ERC20/ERC6909
- **ReentrancyProtection.sol**: EIP-1153 transient storage reentrancy guard

## ERC Standards
- ERC-20, ERC-1404 (security token restrictions), ERC-2612 (permit)
- ERC-4626 (tokenized vault, SyncDepositVault)
- ERC-6909 (multi-token holdings)
- ERC-7540 (async vault), ERC-7575 (multi-asset vault), ERC-7741 (authorized operators), ERC-7887 (cancellation)
- ERC-7714 (permissioned), ERC-7751 (wrapped errors)

## Codebase Scale
- 164 Solidity files, ~11,855 nSLOC
- Solidity 0.8.28, Cancun EVM
- 19 prior security reviews
