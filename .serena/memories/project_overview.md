# Centrifuge Protocol V3.1 - Project Overview

## Project Purpose
This is a **security audit repository** for Centrifuge Protocol V3.1, part of a Sherlock audit contest. The repository contains the smart contract codebase for auditing purposes.

**Centrifuge Protocol** is an open-source, decentralized protocol for tokenizing and distributing financial products across multiple blockchain networks. It provides infrastructure for creating customizable asset management products with seamless multi-chain deployment.

## Audit Context
- **Audit Platform**: Sherlock
- **Contest Type**: Security audit with conditional pot (100,000-250,000 USDC)
- **Commit Hash**: `88ccb68bcd653a326a54d1a724a06f3c5dbc5e6f`
- **Previous Version**: v3.0.1 (commit: `7ca5819788f6d28d8481932b237951c1ffb7ff3b`)
- **Security Reviews**: 19 previous audits
- **Documentation**: https://v3-1.documentation-569.pages.dev/developer/protocol/overview/

## Target Chains
- Ethereum
- Base
- Arbitrum
- Avalanche
- BNB Smart Chain
- Plume

## Key Features
1. **Multi-chain asset management** - Hub-and-spoke model with chain abstraction
2. **Standards-based composability** - ERC-20, ERC-1404, ERC-2612, ERC-4626, ERC-6909, ERC-7540, ERC-7575
3. **Immutable core, modular extensions** - Customizable vaults, hooks, managers
4. **Onchain accounting** - Double-entry bookkeeping system across chains
5. **One-click deployment** - Monolithic contracts for easy deployment

## Tech Stack
- **Language**: Solidity 0.8.28
- **EVM Version**: Cancun
- **Framework**: Foundry (Forge)
- **Forge Version**: 1.3.2-stable
- **Testing**: Foundry test suite
- **Static Analysis**: Slither
- **Cross-chain**: LayerZero, Wormhole, Axelar adapters

## Architecture
```
Hub Chain (Central Control)
├── Pool management
├── Accounting (double-entry bookkeeping)
├── Holdings ledger
├── NAV calculations
└── Price oracle updates

Spoke Chains (Tokenization & Distribution)
├── ERC-20 share tokens
├── Transfer hooks (compliance)
├── ERC-4626/ERC-7540 vaults
└── Multi-asset support
```

## Areas of Concern (from README)
1. Pool managers manipulating other pools
2. Malicious adapters creating cross-pool batches
3. Cross-chain message ordering and race conditions
4. Price manipulation via SimplePriceManager
5. LayerZero front-running attacks
6. Arbitrage in multi-asset pools

## Main Changes in V3.1
- Separated ShareClassManager → BatchRequestManager + ShareClassManager
- Simplified Spoke contract, separate VaultRegistry
- New QueueManager for balance sheet synchronization
- New NAVManager for NAV calculations
- New SimplePriceManager for automated pricing
- New OracleValuation contract
- Support for UpdateContract from spoke to hub
- Refactored hooks to BaseTransferHook
- Simplified gateway changes
- Separate protocol and ops guardian

## Known Issues
See README.md lines 68-92 for comprehensive list of known/acceptable risks including:
- SimplePriceManager price manipulation
- LayerZero front-running
- Cross-chain message ordering issues
- Liquidity freezing scenarios
- Guardian Safe integration requirements
