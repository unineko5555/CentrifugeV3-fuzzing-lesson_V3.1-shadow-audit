// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera deps
import {vm} from "@chimera/Hevm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

// Source types
import {PoolId, newPoolId} from "src/core/types/PoolId.sol";
import {AssetId, newAssetId, centrifugeId as assetCentrifugeId} from "src/core/types/AssetId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AccountId} from "src/core/types/AccountId.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {JournalEntry} from "src/core/hub/interfaces/IAccounting.sol";
import {IValuation} from "src/core/hub/interfaces/IValuation.sol";
import {IHubRequestManager} from "src/core/hub/interfaces/IHubRequestManager.sol";

// Targets
import {AdminTargets} from "./targets/AdminTargets.sol";
import {HubTargets} from "./targets/HubTargets.sol";
import {HubHandlerTargets} from "./targets/HubHandlerTargets.sol";
import {BatchRequestTargets} from "./targets/BatchRequestTargets.sol";
import {NAVTargets} from "./targets/NAVTargets.sol";
import {ManagerTargets} from "./targets/ManagerTargets.sol";
import {ToggleTargets} from "./targets/ToggleTargets.sol";
import {DoomsdayTargets} from "./targets/DoomsdayTargets.sol";

// Utils
import {Helpers} from "./utils/Helpers.sol";
import {OpType} from "./BeforeAfter.sol";

abstract contract TargetFunctions is
    AdminTargets,
    HubTargets,
    HubHandlerTargets,
    BatchRequestTargets,
    NAVTargets,
    ManagerTargets,
    ToggleTargets,
    DoomsdayTargets
{
    /// @dev Pools created with OracleValuation (for clamped oracle targets)
    PoolId[] internal oraclePoolIds;

    /// === SHORTCUT FUNCTIONS === ///

    /// @dev Create pool + share class + holding in one call
    function shortcut_create_pool_and_holding(uint8 decimals, uint32 isoCode, uint256 salt, bool isIdentityValuation)
        public
        clearQueuedCalls
        returns (PoolId poolId, ShareClassId scId)
    {
        decimals %= 24;
        require(decimals >= 6, "decimals must be >= 6");

        // Add and register asset — encode centrifugeId in top bits
        add_new_asset(decimals);
        uint128 encodedAssetId = newAssetId(CENTRIFUGE_CHAIN_ID, isoCode).raw();
        hub_registerAsset(encodedAssetId);

        // Create pool (admin = address(this)) — encode centrifugeId in top 16 bits
        uint64 rawPoolId = uint64(uint64(CENTRIFUGE_CHAIN_ID) << 48) | uint64(POOL_ID_COUNTER++);
        poolId = hub_createPool(address(this), rawPoolId, encodedAssetId);

        // Setup BRM as request manager for this pool
        hubRegistry.updateManager(poolId, address(this), true);
        hubRegistry.setHubRequestManager(poolId, CENTRIFUGE_CHAIN_ID, IHubRequestManager(address(brm)));
        hubRegistry.updateManager(poolId, address(brm), true);

        // Setup NAVManager as manager
        navManager.updateManager(poolId, address(this), true);

        // Setup OracleValuation: make test contract a feeder for this pool
        oracleValuation.updateFeeder(poolId, address(this), true);

        // Create share class and holding
        scId = shareClassManager.previewNextShareClassId(poolId);
        shortcut_add_share_class_and_holding(poolId.raw(), salt, scId.raw(), isIdentityValuation);

        return (poolId, scId);
    }

    /// @dev Add share class + create accounts + initialize holding
    function shortcut_add_share_class_and_holding(
        uint64 poolId,
        uint256 salt,
        bytes16 scId,
        bool isIdentityValuation
    ) public {
        hub_addShareClass(poolId, salt);

        IValuation valuation =
            isIdentityValuation ? IValuation(address(identityValuation)) : IValuation(address(mockValuation));

        hub_createAccount(poolId, ASSET_ACCOUNT, IS_DEBIT_NORMAL);
        hub_createAccount(poolId, EQUITY_ACCOUNT, IS_DEBIT_NORMAL);
        hub_createAccount(poolId, LOSS_ACCOUNT, IS_DEBIT_NORMAL);
        hub_createAccount(poolId, GAIN_ACCOUNT, IS_DEBIT_NORMAL);

        hub_initializeHolding(poolId, scId, valuation, ASSET_ACCOUNT, EQUITY_ACCOUNT, LOSS_ACCOUNT, GAIN_ACCOUNT);
    }

    /// @dev Deposit shortcut: create pool → request deposit → approve → issue
    function shortcut_deposit(
        uint8 decimals,
        uint32 isoCode,
        uint256 salt,
        bool isIdentityValuation,
        uint128 amount,
        uint128 maxApproval,
        uint128 navPerShare
    ) public clearQueuedCalls returns (PoolId poolId, ShareClassId scId) {
        decimals %= 24;
        require(decimals >= 6, "decimals must be >= 6");

        (poolId, scId) = shortcut_create_pool_and_holding(decimals, isoCode, salt, isIdentityValuation);

        // Request deposit via BRM
        brm_requestDeposit(poolId.raw(), scId.raw(), amount);

        // Approve and issue shares
        shortcut_approve_and_issue_shares(poolId.raw(), scId.raw(), isoCode, maxApproval, isIdentityValuation, navPerShare);

        return (poolId, scId);
    }

    /// @dev Deposit + claim shortcut
    function shortcut_deposit_and_claim(
        uint8 decimals,
        uint32 isoCode,
        uint256 salt,
        bool isIdentityValuation,
        uint128 amount,
        uint128 maxApproval,
        uint128 navPerShare
    ) public clearQueuedCalls returns (PoolId poolId, ShareClassId scId) {
        decimals %= 24;
        require(decimals >= 6, "decimals must be >= 6");

        (poolId, scId) =
            shortcut_deposit(decimals, isoCode, salt, isIdentityValuation, amount, maxApproval, navPerShare);

        AssetId assetId = newAssetId(CENTRIFUGE_CHAIN_ID, isoCode);
        hub_notifyDeposit(poolId.raw(), scId.raw(), assetId.raw(), MAX_CLAIMS);

        return (poolId, scId);
    }

    /// @dev Approve deposits + issue shares
    function shortcut_approve_and_issue_shares(
        uint64 poolId,
        bytes16 scId,
        uint32 isoCode,
        uint128 maxApproval,
        bool isIdentityValuation,
        uint128 navPerShare
    ) public {
        AssetId assetId = newAssetId(CENTRIFUGE_CHAIN_ID, isoCode);

        // Set valuation price for mock
        if (!isIdentityValuation) {
            mockValuation.setPrice(PoolId.wrap(poolId), ShareClassId.wrap(scId), assetId, INITIAL_PRICE);
        }

        uint32 nowDepositEpoch = brm.nowDepositEpoch(PoolId.wrap(poolId), ShareClassId.wrap(scId), assetId);
        uint32 nowIssueEpoch = brm.nowIssueEpoch(PoolId.wrap(poolId), ShareClassId.wrap(scId), assetId);

        brm_approveDeposits(poolId, scId, nowDepositEpoch, maxApproval, INITIAL_PRICE.raw());
        brm_issueShares(poolId, scId, nowIssueEpoch, navPerShare);
    }

    /// @dev Approve redeems + revoke shares
    function shortcut_approve_and_revoke_shares(
        uint64 poolId,
        bytes16 scId,
        uint32 isoCode,
        uint128 maxApproval,
        uint128 navPerShare,
        bool isIdentityValuation
    ) public {
        AssetId assetId = newAssetId(CENTRIFUGE_CHAIN_ID, isoCode);

        // Set valuation price for mock
        if (!isIdentityValuation) {
            mockValuation.setPrice(PoolId.wrap(poolId), ShareClassId.wrap(scId), assetId, INITIAL_PRICE);
        }

        uint32 nowRedeemEpoch = brm.nowRedeemEpoch(PoolId.wrap(poolId), ShareClassId.wrap(scId), assetId);
        uint32 nowRevokeEpoch = brm.nowRevokeEpoch(PoolId.wrap(poolId), ShareClassId.wrap(scId), assetId);

        brm_approveRedeems(poolId, scId, nowRedeemEpoch, maxApproval, INITIAL_PRICE.raw());
        brm_revokeShares(poolId, scId, nowRevokeEpoch, navPerShare);
    }

    /// @dev Redeem shortcut
    function shortcut_redeem(
        uint64 poolId,
        bytes16 scId,
        uint128 shareAmount,
        uint32 isoCode,
        uint128 maxApproval,
        uint128 navPerShare,
        bool isIdentityValuation
    ) public clearQueuedCalls {
        brm_requestRedeem(poolId, scId, shareAmount);
        shortcut_approve_and_revoke_shares(poolId, scId, isoCode, maxApproval, navPerShare, isIdentityValuation);
    }

    /// @dev Redeem + claim shortcut
    function shortcut_redeem_and_claim(
        uint64 poolId,
        bytes16 scId,
        uint128 shareAmount,
        uint32 isoCode,
        uint128 maxApproval,
        uint128 navPerShare,
        bool isIdentityValuation
    ) public clearQueuedCalls {
        shortcut_redeem(poolId, scId, shareAmount, isoCode, maxApproval, navPerShare, isIdentityValuation);
        AssetId assetId = newAssetId(CENTRIFUGE_CHAIN_ID, isoCode);
        hub_notifyRedeem(poolId, scId, assetId.raw(), MAX_CLAIMS);
    }

    /// @dev Update valuation shortcut
    function shortcut_update_valuation(uint8 decimals, uint32 isoCode, uint256 salt, bool isIdentityValuation)
        public
        clearQueuedCalls
        returns (PoolId poolId, ShareClassId scId)
    {
        decimals %= 24;
        require(decimals >= 6, "decimals must be >= 6");

        (poolId, scId) = shortcut_create_pool_and_holding(decimals, isoCode, salt, isIdentityValuation);
        AssetId assetId = newAssetId(CENTRIFUGE_CHAIN_ID, isoCode);
        hub_updateHoldingValuation(
            poolId.raw(),
            scId.raw(),
            assetId.raw(),
            isIdentityValuation ? IValuation(address(identityValuation)) : IValuation(address(mockValuation))
        );
    }

    /// @dev MockValuation price setter
    function mockValuation_setPrice(uint64 poolIdAsUint, bytes16 scIdAsBytes, uint128 assetIdAsUint, uint128 price)
        public
    {
        mockValuation.setPrice(
            PoolId.wrap(poolIdAsUint), ShareClassId.wrap(scIdAsBytes), AssetId.wrap(assetIdAsUint), D18.wrap(price)
        );
    }

    function mockValuation_setPrice_clamped(uint64 poolIdEntropy, uint128 price) public {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, 1);
        AssetId assetId = hubRegistry.currency(poolId);
        mockValuation_setPrice(poolId.raw(), scId.raw(), assetId.raw(), price);
    }

    /// @dev OracleValuation price setter (raw)
    function oracleValuation_setPrice(uint64 poolIdAsUint, bytes16 scIdAsBytes, uint128 assetIdAsUint, uint128 price)
        public
        updateGhostsWithType(OpType.SET_ORACLE_PRICE)
    {
        oracleValuation.setPrice(
            PoolId.wrap(poolIdAsUint), ShareClassId.wrap(scIdAsBytes), AssetId.wrap(assetIdAsUint), D18.wrap(price)
        );
    }

    /// @dev OracleValuation price setter (clamped) — only operates on oracle-backed pools
    function oracleValuation_setPrice_clamped(uint64 poolIdEntropy, uint32 scEntropy, uint128 price)
        public
        updateGhostsWithType(OpType.SET_ORACLE_PRICE)
    {
        if (oraclePoolIds.length == 0) return;
        PoolId poolId = oraclePoolIds[uint256(poolIdEntropy) % oraclePoolIds.length];
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scEntropy);
        AssetId assetId = hubRegistry.currency(poolId);
        // Clamp price to reasonable range [0.001, 1000] in D18
        price = uint128(uint256(price) % 1000e18) + 1e15;
        oracleValuation.setPrice(poolId, scId, assetId, D18.wrap(price));
    }

    /// @dev Create pool + share class + holding with OracleValuation
    function shortcut_create_oracle_pool_and_holding(uint8 decimals, uint32 isoCode, uint256 salt)
        public
        clearQueuedCalls
        returns (PoolId poolId, ShareClassId scId)
    {
        decimals %= 24;
        require(decimals >= 6, "decimals must be >= 6");

        // Add and register asset
        add_new_asset(decimals);
        uint128 encodedAssetId = newAssetId(CENTRIFUGE_CHAIN_ID, isoCode).raw();
        hub_registerAsset(encodedAssetId);

        // Create pool
        uint64 rawPoolId = uint64(uint64(CENTRIFUGE_CHAIN_ID) << 48) | uint64(POOL_ID_COUNTER++);
        poolId = hub_createPool(address(this), rawPoolId, encodedAssetId);

        // Setup BRM as request manager for this pool
        hubRegistry.updateManager(poolId, address(this), true);
        hubRegistry.setHubRequestManager(poolId, CENTRIFUGE_CHAIN_ID, IHubRequestManager(address(brm)));
        hubRegistry.updateManager(poolId, address(brm), true);

        // Setup NAVManager + OracleValuation feeder + OracleValuation as hub manager
        navManager.updateManager(poolId, address(this), true);
        hubRegistry.updateManager(poolId, address(oracleValuation), true);
        oracleValuation.updateFeeder(poolId, address(this), true);

        // Create share class
        scId = shareClassManager.previewNextShareClassId(poolId);
        hub_addShareClass(poolId.raw(), salt);

        // Create accounts + initialize holding with OracleValuation
        hub_createAccount(poolId.raw(), ASSET_ACCOUNT, IS_DEBIT_NORMAL);
        hub_createAccount(poolId.raw(), EQUITY_ACCOUNT, IS_DEBIT_NORMAL);
        hub_createAccount(poolId.raw(), LOSS_ACCOUNT, IS_DEBIT_NORMAL);
        hub_createAccount(poolId.raw(), GAIN_ACCOUNT, IS_DEBIT_NORMAL);

        hub_initializeHolding(
            poolId.raw(), scId.raw(), IValuation(address(oracleValuation)),
            ASSET_ACCOUNT, EQUITY_ACCOUNT, LOSS_ACCOUNT, GAIN_ACCOUNT
        );

        // Set initial oracle price so getPrice/getQuote don't revert
        oracleValuation.setPrice(poolId, scId, AssetId.wrap(encodedAssetId), INITIAL_PRICE);

        // Track oracle-enabled pools for clamped targets
        oraclePoolIds.push(poolId);

        return (poolId, scId);
    }

    /// @dev Add share class + create Expense/Liability accounts + initialize liability holding
    function shortcut_add_share_class_and_liability(
        uint64 poolId,
        uint256 salt,
        bytes16 scId,
        bool isIdentityValuation
    ) public {
        hub_addShareClass(poolId, salt);

        IValuation valuation =
            isIdentityValuation ? IValuation(address(identityValuation)) : IValuation(address(mockValuation));

        // Create Expense + Liability accounts (different from asset holding accounts)
        hub_createAccount(poolId, EXPENSE_ACCOUNT, true); // Expense = debit normal
        hub_createAccount(poolId, LIABILITY_ACCOUNT, false); // Liability = credit normal

        hub_initializeLiability(poolId, scId, valuation, EXPENSE_ACCOUNT, LIABILITY_ACCOUNT);
    }

    /// @dev Create pool + share class + liability holding in one call
    function shortcut_create_pool_and_liability(
        uint8 decimals,
        uint32 isoCode,
        uint256 salt,
        bool isIdentityValuation
    ) public clearQueuedCalls returns (PoolId poolId, ShareClassId scId) {
        decimals %= 24;
        require(decimals >= 6, "decimals must be >= 6");

        // Add and register asset
        add_new_asset(decimals);
        uint128 encodedAssetId = newAssetId(CENTRIFUGE_CHAIN_ID, isoCode).raw();
        hub_registerAsset(encodedAssetId);

        // Create pool
        uint64 rawPoolId = uint64(uint64(CENTRIFUGE_CHAIN_ID) << 48) | uint64(POOL_ID_COUNTER++);
        poolId = hub_createPool(address(this), rawPoolId, encodedAssetId);

        // Setup managers
        hubRegistry.updateManager(poolId, address(this), true);
        hubRegistry.setHubRequestManager(poolId, CENTRIFUGE_CHAIN_ID, IHubRequestManager(address(brm)));
        hubRegistry.updateManager(poolId, address(brm), true);
        navManager.updateManager(poolId, address(this), true);
        oracleValuation.updateFeeder(poolId, address(this), true);

        // Create share class and liability holding
        scId = shareClassManager.previewNextShareClassId(poolId);
        shortcut_add_share_class_and_liability(poolId.raw(), salt, scId.raw(), isIdentityValuation);

        return (poolId, scId);
    }

    /// @dev Gateway subsidy
    function gateway_subsidizePool(uint64 poolId) public payable {
        gateway.subsidizePool{value: msg.value}(poolId);
    }

    /// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///
}
