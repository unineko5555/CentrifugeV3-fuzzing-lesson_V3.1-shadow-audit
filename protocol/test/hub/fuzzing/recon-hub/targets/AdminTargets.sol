// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera deps
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";
import {MockERC20} from "@recon/MockERC20.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId, newAssetId} from "src/core/types/AssetId.sol";
import {AccountId} from "src/core/types/AccountId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {D18} from "src/misc/types/D18.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";
import {JournalEntry} from "src/core/hub/interfaces/IAccounting.sol";

// Interfaces
import {IValuation} from "src/core/hub/interfaces/IValuation.sol";

// Utils
import {Helpers} from "../utils/Helpers.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";
import {console2} from "forge-std/console2.sol";

abstract contract AdminTargets is BaseTargetFunctions, Properties {
    using CastLib for *;

    // ========================================================================
    // Share Class Management
    // ========================================================================

    function hub_addShareClass(uint64 poolIdAsUint, uint256 salt) public {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        string memory name = "Test ShareClass";
        string memory symbol = "TSC";
        hub.addShareClass(poolId, name, symbol, bytes32(salt));
    }

    function hub_addShareClass_clamped(uint64 poolIdEntropy, uint256 salt) public {
        PoolId poolId = Helpers.getRandomPoolId(createdPools, poolIdEntropy);
        hub_addShareClass(poolId.raw(), salt);
    }

    // ========================================================================
    // Account Management
    // ========================================================================

    function hub_createAccount(uint64 poolIdAsUint, uint32 accountAsInt, bool isDebitNormal) public {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        AccountId account = AccountId.wrap(accountAsInt);
        hub.createAccount(poolId, account, isDebitNormal);
    }

    // ========================================================================
    // Holding Initialization
    // ========================================================================

    function hub_initializeHolding(
        uint64 poolIdAsUint,
        bytes16 scIdAsBytes,
        IValuation valuation,
        uint32 assetAccountAsUint,
        uint32 equityAccountAsUint,
        uint32 lossAccountAsUint,
        uint32 gainAccountAsUint
    ) public {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = hubRegistry.currency(poolId);

        hub.initializeHolding(
            poolId,
            scId,
            assetId,
            valuation,
            AccountId.wrap(assetAccountAsUint),
            AccountId.wrap(equityAccountAsUint),
            AccountId.wrap(gainAccountAsUint),
            AccountId.wrap(lossAccountAsUint)
        );

        createdAccountIds.push(AccountId.wrap(assetAccountAsUint));
        createdAccountIds.push(AccountId.wrap(equityAccountAsUint));
        createdAccountIds.push(AccountId.wrap(lossAccountAsUint));
        createdAccountIds.push(AccountId.wrap(gainAccountAsUint));
    }

    function hub_initializeHolding_clamped(
        uint64 poolIdEntropy,
        uint32 scEntropy,
        bool isIdentityValuation,
        uint32 assetAccountAsUint,
        uint32 equityAccountAsUint,
        uint32 lossAccountAsUint,
        uint32 gainAccountAsUint
    ) public {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);
        IValuation valuation =
            isIdentityValuation ? IValuation(address(identityValuation)) : IValuation(address(mockValuation));

        hub_initializeHolding(
            poolId.raw(), scId.raw(), valuation, assetAccountAsUint, equityAccountAsUint, lossAccountAsUint, gainAccountAsUint
        );
    }

    // ========================================================================
    // Holding Updates
    // ========================================================================

    function hub_updateHoldingValue(uint64 poolIdAsUint, bytes16 scIdAsBytes, uint128 assetIdAsUint)
        public
        updateGhosts
    {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = AssetId.wrap(assetIdAsUint);
        hub.updateHoldingValue(poolId, scId, assetId);
    }

    function hub_updateHoldingValue_clamped(uint64 poolEntropy, uint32 scEntropy) public updateGhosts {
        PoolId poolId = _getRandomPoolId(poolEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);
        AssetId assetId = hubRegistry.currency(poolId);
        hub_updateHoldingValue(poolId.raw(), scId.raw(), assetId.raw());
    }

    function hub_updateHoldingValuation(
        uint64 poolIdAsUint,
        bytes16 scIdAsBytes,
        uint128 assetIdAsUint,
        IValuation valuation
    ) public updateGhosts {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = AssetId.wrap(assetIdAsUint);
        hub.updateHoldingValuation(poolId, scId, assetId, valuation);
    }

    // ========================================================================
    // Share Price
    // ========================================================================

    function hub_updateSharePrice(uint64 poolIdAsUint, bytes16 scIdAsBytes, uint128 pricePoolPerShare, uint64 computedAt)
        public
        updateGhosts
    {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        hub.updateSharePrice(poolId, scId, D18.wrap(pricePoolPerShare), computedAt);
    }

    function hub_updateSharePrice_clamped(uint64 poolIdEntropy, uint32 scEntropy, uint128 price) public {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);
        hub_updateSharePrice(poolId.raw(), scId.raw(), price, uint64(block.timestamp));
    }

    // ========================================================================
    // Journal
    // ========================================================================

    function hub_updateJournal(uint64 poolIdAsUint, JournalEntry[] memory debits, JournalEntry[] memory credits)
        public
        updateGhosts
    {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        hub.updateJournal(poolId, debits, credits);
    }

    // ========================================================================
    // Notifications
    // ========================================================================

    function hub_notifyPool(uint64 poolIdAsUint, uint16 centrifugeId) public {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        hub.notifyPool(poolId, centrifugeId, address(0));
    }

    function hub_notifyShareClass(uint64 poolIdAsUint, uint16 centrifugeId, bytes16 scIdAsBytes, bytes32 hook)
        public
    {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        hub.notifyShareClass(poolId, scId, centrifugeId, hook, address(0));
    }

    function hub_notifyShareClass_clamped(uint64 poolIdEntropy, uint32 scEntropy, bytes32 hook) public {
        PoolId poolId = Helpers.getRandomPoolId(createdPools, poolIdEntropy);
        ShareClassId scId = Helpers.getRandomShareClassIdForPool(shareClassManager, poolId, scEntropy);
        hub_notifyShareClass(poolId.raw(), CENTRIFUGE_CHAIN_ID, scId.raw(), hook);
    }

    // ========================================================================
    // Asset Registration
    // ========================================================================

    function hub_registerAsset(uint128 assetIdAsUint) public updateGhosts {
        AssetId assetId_ = AssetId.wrap(assetIdAsUint);
        uint8 decimals = MockERC20(_getAsset()).decimals();
        hubRegistry.registerAsset(assetId_, decimals);
        createdAssetIds.push(assetId_);
    }

    // ========================================================================
    // Restriction
    // ========================================================================

    function hub_updateRestriction(uint64 poolIdAsUint, bytes16 scIdAsBytes, uint16 chainId, bytes calldata payload)
        public
    {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        hub.updateRestriction(poolId, scId, chainId, payload, 0, address(0));
    }

    // ========================================================================
    // Metadata
    // ========================================================================

    function hub_setPoolMetadata(uint64 poolIdAsUint, bytes memory metadata) public {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        hub.setPoolMetadata(poolId, metadata);
    }

    function hub_setAccountMetadata(uint64 poolIdAsUint, uint32 accountAsInt, bytes memory metadata) public {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        AccountId account = AccountId.wrap(accountAsInt);
        hub.setAccountMetadata(poolId, account, metadata);
    }

    function hub_setHoldingAccountId(
        uint64 poolIdAsUint,
        bytes16 scIdAsBytes,
        uint128 assetIdAsUint,
        uint8 kind,
        uint32 accountIdAsInt
    ) public {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = AssetId.wrap(assetIdAsUint);
        AccountId accountId = AccountId.wrap(accountIdAsInt);
        hub.setHoldingAccountId(poolId, scId, assetId, kind, accountId);
    }
}
