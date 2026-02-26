// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {Test, console2} from "forge-std/Test.sol";

import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId, newAssetId} from "src/core/types/AssetId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AccountId} from "src/core/types/AccountId.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {JournalEntry} from "src/core/hub/interfaces/IAccounting.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";

import {TargetFunctions} from "./TargetFunctions.sol";
import {Helpers} from "./utils/Helpers.sol";

// forge test --match-contract CryticToFoundry --match-path test/hub/fuzzing/recon-hub/CryticToFoundry.t.sol -vv
contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    uint128 constant INVESTOR_AMOUNT = 100 * 1e6;
    uint128 constant SHARE_AMOUNT = 10 * 1e18;
    uint128 constant APPROVED_INVESTOR_AMOUNT = INVESTOR_AMOUNT / 5;
    uint128 constant APPROVED_SHARE_AMOUNT = SHARE_AMOUNT / 5;
    uint128 NAV_PER_SHARE = 2 * 1e18;

    PoolId poolId;
    ShareClassId scId;
    AssetId assetId;

    function setUp() public {
        setup();
    }

    /// === Smoke Tests === ///

    function test_setup_deploys_correctly() public view {
        assertTrue(address(hub) != address(0), "hub not deployed");
        assertTrue(address(brm) != address(0), "brm not deployed");
        assertTrue(address(navManager) != address(0), "navManager not deployed");
        assertTrue(address(oracleValuation) != address(0), "oracleValuation not deployed");
        assertTrue(address(hubHandler) != address(0), "hubHandler not deployed");
    }

    function test_create_pool_and_holding() public {
        (poolId, scId) = shortcut_create_pool_and_holding(18, 123, 1, true);
        assertTrue(createdPools.length > 0, "no pools created");
    }

    function test_deposit_flow() public {
        (poolId, scId) =
            shortcut_deposit_and_claim(18, 123, 1, true, INVESTOR_AMOUNT, APPROVED_INVESTOR_AMOUNT, NAV_PER_SHARE);
        assertTrue(poolCreated, "pool not created");
    }

    function test_deposit_and_cancel() public {
        (poolId, scId) = shortcut_deposit(18, 123, 1, true, INVESTOR_AMOUNT, APPROVED_INVESTOR_AMOUNT, NAV_PER_SHARE);
        brm_cancelDepositRequest(poolId.raw(), scId.raw());
    }

    function test_redeem_flow() public {
        (poolId, scId) =
            shortcut_deposit_and_claim(18, 123, 1, true, INVESTOR_AMOUNT, APPROVED_INVESTOR_AMOUNT, NAV_PER_SHARE);
        shortcut_redeem_and_claim(poolId.raw(), scId.raw(), SHARE_AMOUNT, 123, APPROVED_SHARE_AMOUNT, NAV_PER_SHARE, true);
    }

    /// === Property Tests === ///

    function test_property_accounting_and_holdings_soundness() public {
        shortcut_create_pool_and_holding(18, 123, 1, true);
        property_accounting_and_holdings_soundness();
    }

    function test_property_brm_deposit_epoch_monotonic() public {
        shortcut_create_pool_and_holding(18, 123, 1, true);
        property_brm_deposit_epoch_monotonic();
    }

    function test_property_brm_pending_deposit_accounting() public {
        shortcut_deposit(18, 123, 1, true, INVESTOR_AMOUNT, APPROVED_INVESTOR_AMOUNT, NAV_PER_SHARE);
        property_brm_pending_deposit_accounting();
    }

    function test_property_asset_soundness() public {
        shortcut_create_pool_and_holding(18, 123, 1, true);
        property_asset_soundness();
    }

    /// === Reproducers === ///
    // Add fuzzer-discovered reproducers here
}
