# Centrifuge Protocol V3.1  contest details

- Join [Sherlock Discord](https://discord.gg/MABEWyASkp)
- Submit findings using the **Issues** page in your private contest repo (label issues as **Medium** or **High**)
- [Read for more details](https://docs.sherlock.xyz/audits/watsons)

# Q&A

### Q: On what chains are the smart contracts going to be deployed?
Ethereum, Base, Arbitrum, Avalanche, BNB Smart Chain, Plume
___

### Q: If you are integrating tokens, are you allowing only whitelisted tokens to work with the codebase or any complying with the standard? Are they assumed to have certain properties, e.g. be non-reentrant? Are there any types of [weird tokens](https://github.com/d-xo/weird-erc20) you want to integrate?
Protocol only supports standard tokens with 2-18 decimals (decimals are enforced in Spoke.sol contract), no weird tokens.
___

### Q: Are there any limitations on values set by admins (or other roles) in the codebase, including restrictions on array lengths?
Pool manager roles are fully trusted within the context of the pool. Pool manager roles include the hub manager, balance sheet manager, gateway manager, request manager, and hook manager.

Similarly, custom gateway adapters and transfer hooks should be able to do anything in their set pool (ie, trusted), but shouldn't be able to do anything outside of their pool, and can be considered untrusted (in the context of other pools).

Relayers on the on/off ramp manager are fully trusted to decide withdrawal destinations for assets in their pool.

Merkle proof manager strategists are fully trusted to execute calls allowed within the policy set for that pool.
___

### Q: Are there any limitations on values set by admins (or other roles) in protocols you integrate with, including restrictions on array lengths?
No.
___

### Q: Is the codebase expected to comply with any specific EIPs?
ERC-20: issued share tokens, as well as holdings on the balance sheet of a pool.
ERC-1404: standardized compliance checks for share tokens.
ERC-2612: permit functionality built in to share tokens.
ERC-4626: tokenized vault standard, used for synchronous deposit vaults.
ERC-6909: holdings of multi-tokens on the balance sheet of a pool.
ERC-7540: asynchronous vault standard, used for asynchronous vault logic.
ERC-7575: multi-asset vault standard, to allow multiple investment assets per share token.

Issues related to EIP non-compliance can be valid only if they lead to Medium or High impact, besides the EIP violation itself.
___

### Q: Are there any off-chain mechanisms involved in the protocol (e.g., keeper bots, arbitrage bots, etc.)? We assume these mechanisms will not misbehave, delay, or go offline unless otherwise specified.
There will be off-chain keepers for:

- Calling `notifyDeposit/notifyRedeem`  for investor request claiming, based on the events from the `BatchRequestManager`.
- Repaying underpaid transactions (e.g. price updates from `SimplePriceManager` ), based on events from the `Gateway`.
- Calling `QueueManager.sync`, based on events from the `BalanceSheet`.
- Calling `OnOfframpManager.deposit`, based on transfers to the on/offramp manager contract.
___

### Q: What properties/invariants do you want to hold even if breaking them has a low/unknown impact?
-
___

### Q: Please discuss any design choices you made.
See docs, e.g.
- Cross-chain design: https://v3-1.documentation-569.pages.dev/developer/protocol/features/chain-abstraction/
- Modularity: https://v3-1.documentation-569.pages.dev/developer/protocol/features/modularity/
- Technical architecture: https://v3-1.documentation-569.pages.dev/developer/protocol/architecture/overview/

It is assumed that the global adapter set as well as every pool adapter set contains at least 2 adapters, thus any single adapter being compromised will not lead to a compromise of the system.
___

### Q: Please provide links to previous audits (if any) and all the known issues or acceptable risks.
Audits: https://v3-1.documentation-569.pages.dev/developer/protocol/security/

Known issues:
- Ability to manipulate prices of the SimplePriceManager if on/offramp manager or sync deposits are enabled is known (by depositing to raise assets) => it is up to the pool manager to manage this, e.g. by using max reserve.
- Prices computed in SimplePriceManager may be off if approve and issue or approve and revoke are called separately, as then assets and shares are imbalanced.
- SimplePriceManager.onUpdate may revert, when the ShareClassManager issuance is negative, due to a transfer of shares before a submitQueuedShares, blocking updating a holding value.
- Arbitrage in multi-asset pools is pool manager controlled.
- LayerZero executions on target chain can be front-run and forced to go into failed messages queue.
- Hub.createPool can be frontrun leading to griefing
- Any issue related to arbitrage between different assets/currencies in the same pool. Should be managed by pool manager
- Any arbitrage related to cross-chain price updates
- Issues related to cross-chain messages not being executed for a long time, in the wrong order or create race-conditions
- GasService estimate is under/overestimated.
- Subsidized funds can be spammed: we will add min investment limits to alleviate this.
- AsyncRequest._withdraw() using current pricePoolPerAsset which is potentially unlikely pricePoolPerAsset during approval of redemption
- Only deployed on chains with Cancun EVM support. And no zksync.
- After Root.relySchedule executes, the timelock does not apply anymore => intentional, combined with spell pattern it works
- Guardian only works with Safe, if the admin is not a Safe the pause can only be executed by the full Safe and not individual owners
- Liquidity can be stuck if a user is frozen
- Liquidity can be stuck if all vaults are unlinked
- While paused, users can still claim assets/shares
- Auth pattern does not check that there is at least 1 ward
- Manager needs to ensure hooks across domains are compatible
- User needs to ensure they transfer valid share tokens eg member
- Issues with underlying networks being compromised affecting the pools deployed on that network
- Missing existence checks in Hub for pool/sc/asset and other IDs
- Updating vault or request manager can cause loss of pending request state
___

### Q: Please list any relevant protocol resources.
Docs: https://v3-1.documentation-569.pages.dev/developer/protocol/overview/

v3.0.1 commit hash to compare: https://github.com/centrifuge/protocol/tree/7ca5819788f6d28d8481932b237951c1ffb7ff3b
___

### Q: Additional audit information.
Severity clarifications:
1. The DOS-related issues can be considered High severity only if they lead to a permanent lock of funds without a way to retrieve/recover them. If the funds can be recovered and the DOS is only temporary, the issue can be Medium at most.
2. Bypassing any hook check can be considered Medium-severity at most (if leads to Medium impact).
3. Issues that lead to stealing or loss of native tokens stored in the RefundEscrow for gas can be Medium at most.
4. Issues with underlying networks being compromised affecting the pools deployed on that network are out of scope.
5. Issues that are caused by price manipulation (e.g. pool donations) can be Medium at most.

Conditional pot details:
1. If at least 1 High is found the rewards unlocked will be 250,000 USDC
2. There is a guaranteed pot of 100,000 USDC if no High is found

A particular area of concern is pool managers being able to manipulate other pools. Several issues have been found in the past related to this, including:
- A malicious adapter set as a pool adapter, creating a batch that has pool A (its own pool) as the first message, and pool B as the next message(s). Fixed by checking all messages in the batch have the same pool ID.
- A malicious vault factory being used to rely malicious vaults on the existing `AsyncRequestManager`. Fixed by changing the rely flow.

The main changes in v3.1 versus v3.0.1 include:
- Separated `ShareClassManager` to a modular `BatchRequestManager`, and `ShareClassManager` with only the share class logic
- Simplified `Spoke` contract, separate `VaultRegistry`
- New `QueueManager` for automating balance sheet synchronization to the hub
- New `NAVManager` for automating NAV calculations
- New `SimplePriceManager` for automating share price calculations based on the NAV
- New `OracleValuation` contract for manual updates of asset prices
- Support for `UpdateContract` from spoke to hub
- Refactored hooks to a `BaseTransferHook` with simplified implementations on top
- Simplified gateway changes
- Separate protocol and ops guardian


# Audit scope

[protocol @ 88ccb68bcd653a326a54d1a724a06f3c5dbc5e6f](https://github.com/centrifuge/protocol/tree/88ccb68bcd653a326a54d1a724a06f3c5dbc5e6f)
- [protocol/script/CoreDeployer.s.sol](protocol/script/CoreDeployer.s.sol)
- [protocol/script/FullDeployer.s.sol](protocol/script/FullDeployer.s.sol)
- [protocol/script/LaunchDeployer.s.sol](protocol/script/LaunchDeployer.s.sol)
- [protocol/src/adapters/AxelarAdapter.sol](protocol/src/adapters/AxelarAdapter.sol)
- [protocol/src/adapters/interfaces/IAxelarAdapter.sol](protocol/src/adapters/interfaces/IAxelarAdapter.sol)
- [protocol/src/adapters/interfaces/ILayerZeroAdapter.sol](protocol/src/adapters/interfaces/ILayerZeroAdapter.sol)
- [protocol/src/adapters/interfaces/IWormholeAdapter.sol](protocol/src/adapters/interfaces/IWormholeAdapter.sol)
- [protocol/src/adapters/LayerZeroAdapter.sol](protocol/src/adapters/LayerZeroAdapter.sol)
- [protocol/src/adapters/RecoveryAdapter.sol](protocol/src/adapters/RecoveryAdapter.sol)
- [protocol/src/adapters/WormholeAdapter.sol](protocol/src/adapters/WormholeAdapter.sol)
- [protocol/src/admin/OpsGuardian.sol](protocol/src/admin/OpsGuardian.sol)
- [protocol/src/admin/ProtocolGuardian.sol](protocol/src/admin/ProtocolGuardian.sol)
- [protocol/src/admin/Root.sol](protocol/src/admin/Root.sol)
- [protocol/src/admin/TokenRecoverer.sol](protocol/src/admin/TokenRecoverer.sol)
- [protocol/src/core/hub/Accounting.sol](protocol/src/core/hub/Accounting.sol)
- [protocol/src/core/hub/Holdings.sol](protocol/src/core/hub/Holdings.sol)
- [protocol/src/core/hub/HubHandler.sol](protocol/src/core/hub/HubHandler.sol)
- [protocol/src/core/hub/HubRegistry.sol](protocol/src/core/hub/HubRegistry.sol)
- [protocol/src/core/hub/Hub.sol](protocol/src/core/hub/Hub.sol)
- [protocol/src/core/hub/interfaces/IAccounting.sol](protocol/src/core/hub/interfaces/IAccounting.sol)
- [protocol/src/core/hub/interfaces/IHoldings.sol](protocol/src/core/hub/interfaces/IHoldings.sol)
- [protocol/src/core/hub/interfaces/IHub.sol](protocol/src/core/hub/interfaces/IHub.sol)
- [protocol/src/core/hub/interfaces/IShareClassManager.sol](protocol/src/core/hub/interfaces/IShareClassManager.sol)
- [protocol/src/core/hub/ShareClassManager.sol](protocol/src/core/hub/ShareClassManager.sol)
- [protocol/src/core/libraries/PricingLib.sol](protocol/src/core/libraries/PricingLib.sol)
- [protocol/src/core/messaging/GasService.sol](protocol/src/core/messaging/GasService.sol)
- [protocol/src/core/messaging/Gateway.sol](protocol/src/core/messaging/Gateway.sol)
- [protocol/src/core/messaging/interfaces/IGateway.sol](protocol/src/core/messaging/interfaces/IGateway.sol)
- [protocol/src/core/messaging/interfaces/IMultiAdapter.sol](protocol/src/core/messaging/interfaces/IMultiAdapter.sol)
- [protocol/src/core/messaging/libraries/MessageLib.sol](protocol/src/core/messaging/libraries/MessageLib.sol)
- [protocol/src/core/messaging/MessageDispatcher.sol](protocol/src/core/messaging/MessageDispatcher.sol)
- [protocol/src/core/messaging/MessageProcessor.sol](protocol/src/core/messaging/MessageProcessor.sol)
- [protocol/src/core/messaging/MultiAdapter.sol](protocol/src/core/messaging/MultiAdapter.sol)
- [protocol/src/core/spoke/BalanceSheet.sol](protocol/src/core/spoke/BalanceSheet.sol)
- [protocol/src/core/spoke/factories/PoolEscrowFactory.sol](protocol/src/core/spoke/factories/PoolEscrowFactory.sol)
- [protocol/src/core/spoke/factories/TokenFactory.sol](protocol/src/core/spoke/factories/TokenFactory.sol)
- [protocol/src/core/spoke/interfaces/IBalanceSheet.sol](protocol/src/core/spoke/interfaces/IBalanceSheet.sol)
- [protocol/src/core/spoke/interfaces/IPoolEscrow.sol](protocol/src/core/spoke/interfaces/IPoolEscrow.sol)
- [protocol/src/core/spoke/interfaces/IShareToken.sol](protocol/src/core/spoke/interfaces/IShareToken.sol)
- [protocol/src/core/spoke/interfaces/ISpoke.sol](protocol/src/core/spoke/interfaces/ISpoke.sol)
- [protocol/src/core/spoke/interfaces/ITransferHook.sol](protocol/src/core/spoke/interfaces/ITransferHook.sol)
- [protocol/src/core/spoke/interfaces/IVault.sol](protocol/src/core/spoke/interfaces/IVault.sol)
- [protocol/src/core/spoke/PoolEscrow.sol](protocol/src/core/spoke/PoolEscrow.sol)
- [protocol/src/core/spoke/ShareToken.sol](protocol/src/core/spoke/ShareToken.sol)
- [protocol/src/core/spoke/Spoke.sol](protocol/src/core/spoke/Spoke.sol)
- [protocol/src/core/spoke/types/Price.sol](protocol/src/core/spoke/types/Price.sol)
- [protocol/src/core/spoke/VaultRegistry.sol](protocol/src/core/spoke/VaultRegistry.sol)
- [protocol/src/core/types/AccountId.sol](protocol/src/core/types/AccountId.sol)
- [protocol/src/core/types/AssetId.sol](protocol/src/core/types/AssetId.sol)
- [protocol/src/core/types/PoolId.sol](protocol/src/core/types/PoolId.sol)
- [protocol/src/core/types/ShareClassId.sol](protocol/src/core/types/ShareClassId.sol)
- [protocol/src/core/utils/BatchedMulticall.sol](protocol/src/core/utils/BatchedMulticall.sol)
- [protocol/src/core/utils/ContractUpdater.sol](protocol/src/core/utils/ContractUpdater.sol)
- [protocol/src/hooks/BaseTransferHook.sol](protocol/src/hooks/BaseTransferHook.sol)
- [protocol/src/hooks/FreelyTransferable.sol](protocol/src/hooks/FreelyTransferable.sol)
- [protocol/src/hooks/FreezeOnly.sol](protocol/src/hooks/FreezeOnly.sol)
- [protocol/src/hooks/FullRestrictions.sol](protocol/src/hooks/FullRestrictions.sol)
- [protocol/src/hooks/libraries/UpdateRestrictionMessageLib.sol](protocol/src/hooks/libraries/UpdateRestrictionMessageLib.sol)
- [protocol/src/hooks/RedemptionRestrictions.sol](protocol/src/hooks/RedemptionRestrictions.sol)
- [protocol/src/managers/hub/interfaces/ISimplePriceManager.sol](protocol/src/managers/hub/interfaces/ISimplePriceManager.sol)
- [protocol/src/managers/hub/NAVManager.sol](protocol/src/managers/hub/NAVManager.sol)
- [protocol/src/managers/hub/SimplePriceManager.sol](protocol/src/managers/hub/SimplePriceManager.sol)
- [protocol/src/managers/spoke/decoders/BaseDecoder.sol](protocol/src/managers/spoke/decoders/BaseDecoder.sol)
- [protocol/src/managers/spoke/decoders/CircleDecoder.sol](protocol/src/managers/spoke/decoders/CircleDecoder.sol)
- [protocol/src/managers/spoke/decoders/VaultDecoder.sol](protocol/src/managers/spoke/decoders/VaultDecoder.sol)
- [protocol/src/managers/spoke/interfaces/IMerkleProofManager.sol](protocol/src/managers/spoke/interfaces/IMerkleProofManager.sol)
- [protocol/src/managers/spoke/interfaces/IQueueManager.sol](protocol/src/managers/spoke/interfaces/IQueueManager.sol)
- [protocol/src/managers/spoke/MerkleProofManager.sol](protocol/src/managers/spoke/MerkleProofManager.sol)
- [protocol/src/managers/spoke/OnOfframpManager.sol](protocol/src/managers/spoke/OnOfframpManager.sol)
- [protocol/src/managers/spoke/QueueManager.sol](protocol/src/managers/spoke/QueueManager.sol)
- [protocol/src/misc/Auth.sol](protocol/src/misc/Auth.sol)
- [protocol/src/misc/ERC20.sol](protocol/src/misc/ERC20.sol)
- [protocol/src/misc/Escrow.sol](protocol/src/misc/Escrow.sol)
- [protocol/src/misc/libraries/ArrayLib.sol](protocol/src/misc/libraries/ArrayLib.sol)
- [protocol/src/misc/libraries/BitmapLib.sol](protocol/src/misc/libraries/BitmapLib.sol)
- [protocol/src/misc/libraries/BytesLib.sol](protocol/src/misc/libraries/BytesLib.sol)
- [protocol/src/misc/libraries/CastLib.sol](protocol/src/misc/libraries/CastLib.sol)
- [protocol/src/misc/libraries/EIP712Lib.sol](protocol/src/misc/libraries/EIP712Lib.sol)
- [protocol/src/misc/libraries/MathLib.sol](protocol/src/misc/libraries/MathLib.sol)
- [protocol/src/misc/libraries/MerkleProofLib.sol](protocol/src/misc/libraries/MerkleProofLib.sol)
- [protocol/src/misc/libraries/SafeTransferLib.sol](protocol/src/misc/libraries/SafeTransferLib.sol)
- [protocol/src/misc/libraries/SignatureLib.sol](protocol/src/misc/libraries/SignatureLib.sol)
- [protocol/src/misc/libraries/StringLib.sol](protocol/src/misc/libraries/StringLib.sol)
- [protocol/src/misc/libraries/TransientArrayLib.sol](protocol/src/misc/libraries/TransientArrayLib.sol)
- [protocol/src/misc/libraries/TransientBytesLib.sol](protocol/src/misc/libraries/TransientBytesLib.sol)
- [protocol/src/misc/libraries/TransientStorageLib.sol](protocol/src/misc/libraries/TransientStorageLib.sol)
- [protocol/src/misc/Multicall.sol](protocol/src/misc/Multicall.sol)
- [protocol/src/misc/Recoverable.sol](protocol/src/misc/Recoverable.sol)
- [protocol/src/misc/ReentrancyProtection.sol](protocol/src/misc/ReentrancyProtection.sol)
- [protocol/src/misc/types/D18.sol](protocol/src/misc/types/D18.sol)
- [protocol/src/valuations/IdentityValuation.sol](protocol/src/valuations/IdentityValuation.sol)
- [protocol/src/valuations/OracleValuation.sol](protocol/src/valuations/OracleValuation.sol)
- [protocol/src/vaults/AsyncRequestManager.sol](protocol/src/vaults/AsyncRequestManager.sol)
- [protocol/src/vaults/AsyncVault.sol](protocol/src/vaults/AsyncVault.sol)
- [protocol/src/vaults/BaseVaults.sol](protocol/src/vaults/BaseVaults.sol)
- [protocol/src/vaults/BatchRequestManager.sol](protocol/src/vaults/BatchRequestManager.sol)
- [protocol/src/vaults/factories/AsyncVaultFactory.sol](protocol/src/vaults/factories/AsyncVaultFactory.sol)
- [protocol/src/vaults/factories/RefundEscrowFactory.sol](protocol/src/vaults/factories/RefundEscrowFactory.sol)
- [protocol/src/vaults/factories/SyncDepositVaultFactory.sol](protocol/src/vaults/factories/SyncDepositVaultFactory.sol)
- [protocol/src/vaults/interfaces/IBatchRequestManager.sol](protocol/src/vaults/interfaces/IBatchRequestManager.sol)
- [protocol/src/vaults/libraries/RequestCallbackMessageLib.sol](protocol/src/vaults/libraries/RequestCallbackMessageLib.sol)
- [protocol/src/vaults/libraries/RequestMessageLib.sol](protocol/src/vaults/libraries/RequestMessageLib.sol)
- [protocol/src/vaults/RefundEscrow.sol](protocol/src/vaults/RefundEscrow.sol)
- [protocol/src/vaults/SyncDepositVault.sol](protocol/src/vaults/SyncDepositVault.sol)
- [protocol/src/vaults/SyncManager.sol](protocol/src/vaults/SyncManager.sol)
- [protocol/src/vaults/VaultRouter.sol](protocol/src/vaults/VaultRouter.sol)


