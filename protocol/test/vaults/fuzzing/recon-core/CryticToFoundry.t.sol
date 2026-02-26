// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {MockERC20} from "@recon/MockERC20.sol";
import {D18} from "src/misc/types/D18.sol";
import {PoolId} from "src/core/types/PoolId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {IBaseVault} from "src/vaults/interfaces/IBaseVault.sol";

import {TargetFunctions} from "./TargetFunctions.sol";

// forge test --match-contract CryticToFoundry --match-path test/vaults/fuzzing/recon-core/CryticToFoundry.t.sol -vv
contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    /// === SANITY CHECKS === ///

    function test_setup_deploys_correctly() public view {
        assertTrue(address(root) != address(0), "root not deployed");
        assertTrue(address(escrow) != address(0), "escrow not deployed");
        assertTrue(address(spoke) != address(0), "spoke not deployed");
        assertTrue(address(balanceSheet) != address(0), "balanceSheet not deployed");
        assertTrue(address(vaultRegistry) != address(0), "vaultRegistry not deployed");
        assertTrue(address(asyncRequestManager) != address(0), "asyncRequestManager not deployed");
        assertTrue(address(syncManager) != address(0), "syncManager not deployed");
        assertTrue(address(gateway) != address(0), "gateway not deployed");
        assertTrue(address(vaultFactory) != address(0), "vaultFactory not deployed");
        assertTrue(address(fullRestrictions) != address(0), "fullRestrictions not deployed");
    }

    function test_deployNewTokenPoolAndShare() public {
        deployNewTokenPoolAndShare(18, 1_000_000e18);

        assertTrue(address(vault) != address(0), "vault not deployed");
        assertTrue(address(token) != address(0), "token not deployed");
        assertTrue(poolId > 0, "poolId not set");
        assertTrue(assetId > 0, "assetId not set");
    }

    function test_deployNewTokenPoolAndShare_deposit() public {
        deployNewTokenPoolAndShare(18, 1_000_000e18);

        spoke_updatePricePoolPerShare(1e18, type(uint64).max);
        spoke_updateMember(type(uint64).max);

        vault_requestDeposit(1e18, 0);
    }

    function test_deposit_and_fulfill() public {
        deployNewTokenPoolAndShare(18, 1_000_000e18);

        spoke_updatePricePoolPerShare(1e18, type(uint64).max);
        spoke_updateMember(type(uint64).max);

        vault_requestDeposit(1e18, 0);

        asyncRequests_fulfillDepositRequest(1e18 - 1, 1e18, 0, 0, D18.wrap(1e18));

        vault_deposit(1e18 - 1);
    }

    function test_deposit_and_redeem() public {
        deployNewTokenPoolAndShare(18, 1_000_000e18);

        spoke_updatePricePoolPerShare(1e18, type(uint64).max);
        spoke_updateMember(type(uint64).max);

        vault_requestDeposit(1e18, 0);
        asyncRequests_fulfillDepositRequest(1e18 - 1, 1e18, 0, 0, D18.wrap(1e18));
        vault_deposit(1e18 - 1);

        vault_requestRedeem(1e18 - 1, 0);
        asyncRequests_fulfillRedeemRequest(1e18, 1e18 - 1, 0, 0);
        vault_withdraw(1e18, 0);
    }

    function test_deposit_and_cancel() public {
        deployNewTokenPoolAndShare(18, 1_000_000e18);

        spoke_updatePricePoolPerShare(1e18, type(uint64).max);
        spoke_updateMember(type(uint64).max);

        vault_requestDeposit(1e18, 0);
        vault_cancelDepositRequest();
    }

    function test_property_global_1() public {
        deployNewTokenPoolAndShare(18, 1_000_000e18);

        spoke_updatePricePoolPerShare(1e18, type(uint64).max);
        spoke_updateMember(type(uint64).max);

        vault_requestDeposit(1e18, 0);
        asyncRequests_fulfillDepositRequest(1e18 - 1, 1e18, 0, 0, D18.wrap(1e18));
        vault_deposit(1e18 - 1);

        property_global_1();
    }

    function test_doomsday_vault_views() public {
        deployNewTokenPoolAndShare(18, 1_000_000e18);
        spoke_updatePricePoolPerShare(1e18, type(uint64).max);
        spoke_updateMember(type(uint64).max);

        doomsday_vault_views_never_revert();
    }

    /// === NEW PROPERTY TESTS === ///

    function test_property_PE_1() public {
        deployNewTokenPoolAndShare(18, 1_000_000e18);
        spoke_updatePricePoolPerShare(1e18, type(uint64).max);
        spoke_updateMember(type(uint64).max);

        property_PE_1();
    }

    function test_property_PE_3() public {
        deployNewTokenPoolAndShare(18, 1_000_000e18);
        spoke_updatePricePoolPerShare(1e18, type(uint64).max);
        spoke_updateMember(type(uint64).max);

        property_PE_3();
    }

    function test_property_TH_5() public {
        deployNewTokenPoolAndShare(18, 1_000_000e18);
        property_TH_5();
    }

    function test_property_TH_6() public {
        deployNewTokenPoolAndShare(18, 1_000_000e18);
        spoke_updateMember(type(uint64).max);
        property_TH_6();
    }

    function test_property_VR_1() public {
        deployNewTokenPoolAndShare(18, 1_000_000e18);
        property_VR_1();
    }
}
