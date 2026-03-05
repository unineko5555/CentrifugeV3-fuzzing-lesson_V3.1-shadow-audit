// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {Test} from "forge-std/Test.sol";

// Types for E2E tests
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId, newAssetId} from "src/core/types/AssetId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AccountId} from "src/core/types/AccountId.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";
import {IValuation} from "src/core/hub/interfaces/IValuation.sol";
import {JournalEntry} from "src/core/hub/interfaces/IAccounting.sol";
import {IBaseVault} from "src/vaults/interfaces/IBaseVault.sol";

/// @title CryticToFoundry
/// @notice Foundry smoke tests for the E2E fuzzing suite.
///         Validates that the full Hub+Spoke deployment works correctly
///         and that basic E2E flows succeed.
contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    // ===================================================================
    // Setup Verification
    // ===================================================================

    function test_setup_deploys_correctly() public view {
        // Hub core
        assertTrue(address(hub) != address(0), "Hub deployed");
        assertTrue(address(hubHandler) != address(0), "HubHandler deployed");
        assertTrue(address(accounting) != address(0), "Accounting deployed");
        assertTrue(address(hubRegistry) != address(0), "HubRegistry deployed");
        assertTrue(address(holdings) != address(0), "Holdings deployed");
        assertTrue(address(shareClassManager) != address(0), "ShareClassManager deployed");
        assertTrue(address(brm) != address(0), "BatchRequestManager deployed");

        // Hub messaging
        assertTrue(address(hubGateway) != address(0), "Hub Gateway deployed");
        assertTrue(address(hubMultiAdapter) != address(0), "Hub MultiAdapter deployed");
        assertTrue(address(hubMessageProcessor) != address(0), "Hub MessageProcessor deployed");
        assertTrue(address(hubMessageDispatcher) != address(0), "Hub MessageDispatcher deployed");

        // Spoke core
        assertTrue(address(spoke) != address(0), "Spoke deployed");
        assertTrue(address(balanceSheet) != address(0), "BalanceSheet deployed");
        assertTrue(address(vaultRegistry) != address(0), "VaultRegistry deployed");
        assertTrue(address(asyncRequestManager) != address(0), "AsyncRequestManager deployed");

        // Spoke messaging
        assertTrue(address(spokeGateway) != address(0), "Spoke Gateway deployed");
        assertTrue(address(spokeMultiAdapter) != address(0), "Spoke MultiAdapter deployed");
        assertTrue(address(spokeMessageProcessor) != address(0), "Spoke MessageProcessor deployed");
        assertTrue(address(spokeMessageDispatcher) != address(0), "Spoke MessageDispatcher deployed");

        // Bridge
        assertTrue(address(adapterHubToSpoke) != address(0), "Adapter Hub-to-Spoke deployed");
        assertTrue(address(adapterSpokeToHub) != address(0), "Adapter Spoke-to-Hub deployed");

        // Admin
        assertTrue(address(root) != address(0), "Root deployed");
        assertTrue(address(escrow) != address(0), "Escrow deployed");
    }

    function test_hub_messaging_wiring() public view {
        assertEq(address(hubGateway.processor()), address(hubMessageProcessor));
        assertEq(address(hubGateway.adapter()), address(hubMultiAdapter));
        assertEq(address(hubGateway.messageLimits()), address(hubGasService));
        assertEq(address(hub.sender()), address(hubMessageDispatcher));
    }

    function test_spoke_messaging_wiring() public view {
        assertEq(address(spokeGateway.processor()), address(spokeMessageProcessor));
        assertEq(address(spokeGateway.adapter()), address(spokeMultiAdapter));
        assertEq(address(spokeGateway.messageLimits()), address(spokeGasService));
        assertEq(address(spoke.sender()), address(spokeMessageDispatcher));
        assertEq(address(spoke.gateway()), address(spokeGateway));
    }

    function test_bridge_wiring() public view {
        assertEq(address(adapterHubToSpoke.endpoint()), address(adapterSpokeToHub));
        assertEq(address(adapterSpokeToHub.endpoint()), address(adapterHubToSpoke));
        assertEq(adapterHubToSpoke.localCentrifugeId(), HUB_CENTRIFUGE_ID);
        assertEq(adapterSpokeToHub.localCentrifugeId(), SPOKE_CENTRIFUGE_ID);
    }

    function test_hub_core_permissions() public view {
        assertEq(hubRegistry.wards(address(hub)), 1, "Hub is ward on HubRegistry");
        assertEq(accounting.wards(address(hub)), 1, "Hub is ward on Accounting");
        assertEq(holdings.wards(address(hub)), 1, "Hub is ward on Holdings");
        assertEq(shareClassManager.wards(address(hub)), 1, "Hub is ward on ShareClassManager");
        assertEq(hub.wards(address(hubHandler)), 1, "HubHandler is ward on Hub");
        assertEq(holdings.wards(address(hubHandler)), 1, "HubHandler is ward on Holdings");
    }

    function test_spoke_core_permissions() public view {
        assertEq(spoke.wards(address(spokeMessageProcessor)), 1, "MessageProcessor is ward on Spoke");
        assertEq(balanceSheet.wards(address(spokeMessageProcessor)), 1, "MessageProcessor is ward on BalanceSheet");
        assertEq(vaultRegistry.wards(address(spokeMessageProcessor)), 1, "MessageProcessor is ward on VaultRegistry");
        assertEq(balanceSheet.wards(address(asyncRequestManager)), 1, "ARM is ward on BalanceSheet");
        assertEq(escrow.wards(address(asyncRequestManager)), 1, "ARM is ward on Escrow");
    }

    // ===================================================================
    // E2E Pool Creation
    // ===================================================================

    function test_e2e_pool_creation() public {
        admin_createPool(6, 1000e6);

        assertTrue(poolCreated, "Pool should be created");
        assertTrue(vaultDeployed, "Vault should be deployed");
        assertTrue(address(vault) != address(0), "Vault address should be non-zero");
        assertTrue(address(token) != address(0), "Token address should be non-zero");
        assertTrue(createdPools.length > 0, "Should have at least one pool");
    }

    // ===================================================================
    // E2E Cross-System Properties After Setup
    // ===================================================================

    function test_e2e_properties_after_pool_creation() public {
        admin_createPool(6, 1000e6);

        // All properties should hold after fresh pool creation
        property_CS_1_deposit_consistency();
        property_CS_2_share_issuance_balance();
        property_CS_3_escrow_solvency();
        property_CS_5_epoch_monotonicity();
        property_CS_6_share_token_conservation();
        property_CS_9_accounting_equation();

        // Hub accounting
        property_ACC_1_holdings_account_consistency();
        property_ACC_3_asset_soundness();

        // Escrow
        property_E_1_escrow_asset_solvency();
        property_E_2_escrow_share_solvency();

        // Vault
        property_V_1_views_never_revert();
        property_V_2_totalAssets_solvency();
    }

    // ===================================================================
    // E2E Deposit Flow
    // ===================================================================

    function test_e2e_deposit_flow() public {
        admin_createPool(6, 1000e6);

        // Request deposit via BRM
        bytes32 investor = CastLib.toBytes32(address(0x10000));
        uint128 depositAmount = 100e6;

        brm.requestDeposit(activePoolId, activeScId, depositAmount, investor, activeAssetId);

        // Verify pending
        uint128 pending = brm.pendingDeposit(activePoolId, activeScId, activeAssetId);
        assertGe(pending, depositAmount, "Pending should include deposit");

        // P-CS-1 valid here (before approval, epochs match)
        property_CS_1_deposit_consistency();

        // Approve + Issue
        uint32 nowEpoch = brm.nowDepositEpoch(activePoolId, activeScId, activeAssetId);
        brm.approveDeposits(activePoolId, activeScId, activeAssetId, nowEpoch, depositAmount, d18(1e18), address(this));

        uint32 issueEpoch = brm.nowIssueEpoch(activePoolId, activeScId, activeAssetId);
        brm.issueShares(activePoolId, activeScId, activeAssetId, issueEpoch, d18(1e18), 0, address(this));

        // Verify cross-system properties still hold after approval+issue
        property_CS_2_share_issuance_balance();
        property_CS_3_escrow_solvency();
        property_CS_4_price_propagation();
        property_CS_5_epoch_monotonicity();
        property_CS_9_accounting_equation();
    }

    // ===================================================================
    // E2E Accounting Equation
    // ===================================================================

    function test_e2e_accounting_equation() public {
        admin_createPool(6, 1000e6);

        // Do a deposit cycle
        bytes32 investor = CastLib.toBytes32(address(0x10000));
        brm.requestDeposit(activePoolId, activeScId, 50e6, investor, activeAssetId);
        uint32 depEp = brm.nowDepositEpoch(activePoolId, activeScId, activeAssetId);
        brm.approveDeposits(activePoolId, activeScId, activeAssetId, depEp, 50e6, d18(1e18), address(this));
        uint32 issueEp = brm.nowIssueEpoch(activePoolId, activeScId, activeAssetId);
        brm.issueShares(activePoolId, activeScId, activeAssetId, issueEp, d18(1e18), 0, address(this));

        // Accounting equation should hold
        property_CS_9_accounting_equation();
        property_ACC_1_holdings_account_consistency();
        property_ACC_3_asset_soundness();
    }

    // ===================================================================
    // E2E BRM Properties
    // ===================================================================

    function test_e2e_nav_manager_permissions() public {
        admin_createPool(6, 1000e6);

        // NAVManager should be a hub manager for the pool
        assertTrue(hubRegistry.manager(activePoolId, address(navManager)), "NAVManager should be hub manager");
        assertTrue(hubRegistry.manager(activePoolId, address(oracleValuation)), "OracleValuation should be hub manager");

        // Test contract should be a NAVManager manager
        assertTrue(navManager.manager(activePoolId, address(this)), "Test contract should be NAV manager");

        // Network should be initialized (done in createPoolAndSetup)
        assertTrue(navManager.initialized(activePoolId, SPOKE_CENTRIFUGE_ID), "NAV network should be initialized");

        // NAV should be readable and non-zero after a deposit
        uint128 nav = navManager.netAssetValue(activePoolId, SPOKE_CENTRIFUGE_ID);
        // NAV starts at 0 before any deposits
        assertEq(nav, 0, "NAV should be 0 before deposits");

        // Do a deposit cycle to verify NAV updates
        bytes32 investor = CastLib.toBytes32(address(0x10000));
        brm.requestDeposit(activePoolId, activeScId, 100e6, investor, activeAssetId);
        uint32 depEp = brm.nowDepositEpoch(activePoolId, activeScId, activeAssetId);
        brm.approveDeposits(activePoolId, activeScId, activeAssetId, depEp, 100e6, d18(1e18), address(this));
        uint32 issueEp = brm.nowIssueEpoch(activePoolId, activeScId, activeAssetId);
        brm.issueShares(activePoolId, activeScId, activeAssetId, issueEp, d18(1e18), 0, address(this));

        // BRM-only flow doesn't move tokens → Hub holding stays 0 → NAV stays 0
        // To update NAV: deposit actual tokens into PoolEscrow via BalanceSheet, then sync to Hub
        // Must set pricePoolPerAsset first (not yet propagated from Hub to Spoke)
        balanceSheet.overridePricePoolPerAsset(activePoolId, activeScId, activeAssetId, d18(1e18));
        defaultAsset.approve(address(balanceSheet), 100e6);
        balanceSheet.deposit{value: 0}(activePoolId, activeScId, address(defaultAsset), 0, 100e6);

        // Sync queued assets from Spoke to Hub (triggers holdings.increase + updateAccountingAmount)
        AssetId[] memory assetIds = new AssetId[](1);
        assetIds[0] = activeAssetId;
        queueManager.sync{value: 0}(activePoolId, activeScId, assetIds, address(this));

        // After deposit + sync, NAV should reflect the deposited assets
        nav = navManager.netAssetValue(activePoolId, SPOKE_CENTRIFUGE_ID);
        assertGt(nav, 0, "NAV should be > 0 after deposit + sync");

        // Close gain/loss should work (NAVManager has proper permissions)
        navManager.closeGainLoss(activePoolId, SPOKE_CENTRIFUGE_ID);

        // NAV properties
        property_NAV_1_view_liveness();
        property_NAV_2_non_negative();
        property_CS_8_nav_accounting_consistency();
    }

    function test_e2e_oracle_valuation() public {
        admin_createPool(6, 1000e6);

        // Test contract should be a feeder
        assertTrue(oracleValuation.feeder(activePoolId, address(this)), "Test contract should be feeder");

        // Set a price via oracle FIRST (before switching valuation, because
        // updateHoldingValuation internally calls hub.updateHoldingValue which
        // would query the new valuation's getQuote — reverts with PriceNotSet if no price)
        oracleValuation.setPrice(activePoolId, activeScId, activeAssetId, d18(2e18));

        // Now switch valuation (OracleValuation already has the price stored)
        navManager.updateHoldingValuation(
            activePoolId, activeScId, activeAssetId,
            IValuation(address(oracleValuation))
        );

        // Verify the oracle price is used
        D18 price = oracleValuation.getPrice(activePoolId, activeScId, activeAssetId);
        assertEq(D18.unwrap(price), 2e18, "Oracle price should be 2e18");
    }

    function test_e2e_brm_epoch_ordering() public {
        admin_createPool(6, 1000e6);

        // Initial state
        property_BRM_E2E_3_epoch_ordering();

        // After deposit cycle
        bytes32 investor = CastLib.toBytes32(address(0x10000));
        brm.requestDeposit(activePoolId, activeScId, 10e6, investor, activeAssetId);
        uint32 depEp = brm.nowDepositEpoch(activePoolId, activeScId, activeAssetId);
        brm.approveDeposits(activePoolId, activeScId, activeAssetId, depEp, 10e6, d18(1e18), address(this));
        uint32 issueEp = brm.nowIssueEpoch(activePoolId, activeScId, activeAssetId);
        brm.issueShares(activePoolId, activeScId, activeAssetId, issueEp, d18(1e18), 0, address(this));

        // Epoch ordering should still hold
        property_BRM_E2E_3_epoch_ordering();
        property_CS_5_epoch_monotonicity();
    }

    // ===================================================================
    // E2E Price Age
    // ===================================================================

    function test_e2e_price_age_enforcement() public {
        admin_createPool(6, 1000e6);

        // Step 1: Set share price on Hub
        hub.updateSharePrice(activePoolId, activeScId, d18(1e18), uint64(block.timestamp));

        // Step 2: Propagate share price to Spoke via notifySharePrice (Hub → Spoke cross-chain)
        hub.notifySharePrice(activePoolId, activeScId, SPOKE_CENTRIFUGE_ID, address(this));

        // Step 3: Set max price age to 1 hour (Hub → Spoke cross-chain)
        hub.setMaxSharePriceAge{value: 0}(activePoolId, activeScId, SPOKE_CENTRIFUGE_ID, 3600, address(this));

        // Price should be valid now
        spoke.pricePoolPerShare(activePoolId, activeScId, true);

        // Warp forward 2 hours → stale
        vm.warp(block.timestamp + 7200);
        vm.expectRevert();
        spoke.pricePoolPerShare(activePoolId, activeScId, true);
    }

    // ===================================================================
    // E2E Journal
    // ===================================================================

    function test_e2e_journal_balanced() public {
        admin_createPool(6, 1000e6);

        // Use dedicated journal accounts (not holding-tied)
        hub.createAccount(activePoolId, JOURNAL_DEBIT_ACC, true);
        hub.createAccount(activePoolId, JOURNAL_CREDIT_ACC, false);

        JournalEntry[] memory debits = new JournalEntry[](1);
        debits[0] = JournalEntry({value: 100e6, accountId: JOURNAL_DEBIT_ACC});
        JournalEntry[] memory credits = new JournalEntry[](1);
        credits[0] = JournalEntry({value: 100e6, accountId: JOURNAL_CREDIT_ACC});

        hub.updateJournal(activePoolId, debits, credits);
        // Holding-tied properties should still hold
        property_ACC_1_holdings_account_consistency();
        property_CS_9_accounting_equation();
    }

    function test_e2e_journal_unbalanced_reverts() public {
        admin_createPool(6, 1000e6);

        hub.createAccount(activePoolId, JOURNAL_DEBIT_ACC, true);
        hub.createAccount(activePoolId, JOURNAL_CREDIT_ACC, false);

        JournalEntry[] memory debits = new JournalEntry[](1);
        debits[0] = JournalEntry({value: 100e6, accountId: JOURNAL_DEBIT_ACC});
        JournalEntry[] memory credits = new JournalEntry[](1);
        credits[0] = JournalEntry({value: 50e6, accountId: JOURNAL_CREDIT_ACC});

        vm.expectRevert();
        hub.updateJournal(activePoolId, debits, credits);
    }

    // ===================================================================
    // E2E Liability
    // ===================================================================

    function test_e2e_liability_initialization() public {
        admin_createPool(6, 1000e6);

        AssetId liabAssetId = newAssetId(SPOKE_CENTRIFUGE_ID, ASSET_ID_COUNTER);
        ASSET_ID_COUNTER++;
        hubRegistry.registerAsset(liabAssetId, 18);

        navManager.initializeLiability(
            activePoolId, activeScId, liabAssetId,
            IValuation(address(identityValuation))
        );

        assertTrue(holdings.isLiability(activePoolId, activeScId, liabAssetId));
        property_CS_9_accounting_equation();
    }

    // ===================================================================
    // E2E Access Control
    // ===================================================================

    function test_e2e_unauthorized_hub_ops_revert() public {
        admin_createPool(6, 1000e6);
        address unauthorized = address(0xBEEF);
        vm.prank(unauthorized);
        vm.expectRevert();
        hub.updateSharePrice(activePoolId, activeScId, d18(1e18), uint64(block.timestamp));
    }

    // ===================================================================
    // E2E SyncManager
    // ===================================================================

    function test_e2e_sync_manager_set_valuation() public {
        admin_createPool(6, 1000e6);
        // Set valuation to address(0) → SyncManager delegates to spoke.pricePoolPerShare
        syncManager.setValuation(activePoolId, activeScId, address(0));
        // Propagate share price to spoke first
        hub.updateSharePrice(activePoolId, activeScId, d18(1e18), uint64(block.timestamp));
        hub.notifySharePrice(activePoolId, activeScId, SPOKE_CENTRIFUGE_ID, address(this));
        // Now pricePoolPerShare should work via spoke delegation
        D18 price = syncManager.pricePoolPerShare(activePoolId, activeScId);
        assertGt(D18.unwrap(price), 0, "SyncManager price should be > 0");
    }

    function test_e2e_sync_manager_set_max_reserve() public {
        admin_createPool(6, 1000e6);
        (address asset, uint256 tokenId) = spoke.idToAsset(activeAssetId);
        syncManager.setMaxReserve(activePoolId, activeScId, asset, tokenId, 1000e6);
        uint128 res = syncManager.maxReserve(activePoolId, activeScId, asset, tokenId);
        assertEq(res, 1000e6, "maxReserve should be set");
    }

    function test_e2e_sync_manager_convert_views() public {
        admin_createPool(6, 1000e6);
        try syncManager.convertToShares(IBaseVault(address(vault)), 100e6) {} catch {}
        try syncManager.convertToAssets(IBaseVault(address(vault)), 100e18) {} catch {}
    }

    // ===================================================================
    // E2E Hub Notifications
    // ===================================================================

    function test_e2e_hub_notifySharePrice() public {
        admin_createPool(6, 1000e6);
        hub.updateSharePrice(activePoolId, activeScId, d18(1e18), uint64(block.timestamp));
        hub.notifySharePrice(activePoolId, activeScId, SPOKE_CENTRIFUGE_ID, address(this));
        D18 price = spoke.pricePoolPerShare(activePoolId, activeScId, false);
        assertGt(D18.unwrap(price), 0, "Spoke should have share price after notify");
    }

    function test_e2e_hub_notifyAssetPrice() public {
        admin_createPool(6, 1000e6);
        hub.notifyAssetPrice(activePoolId, activeScId, activeAssetId, address(this));
        D18 price = spoke.pricePoolPerAsset(activePoolId, activeScId, activeAssetId, false);
        assertGt(D18.unwrap(price), 0, "Spoke should have asset price after notify");
    }

    function test_e2e_hub_notifyShareMetadata() public {
        admin_createPool(6, 1000e6);
        hub.notifyShareMetadata(activePoolId, activeScId, SPOKE_CENTRIFUGE_ID, address(this));
        string memory name = token.name();
        assertTrue(bytes(name).length > 0, "Token should have name after metadata notify");
    }
}
