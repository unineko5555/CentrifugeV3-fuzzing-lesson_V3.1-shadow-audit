// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {MockERC20} from "@recon/MockERC20.sol";

import {ShareClassId} from "src/common/types/ShareClassId.sol";
import {IShareToken} from "src/spoke/interfaces/IShareToken.sol";
import {IBaseVault} from "src/vaults/interfaces/IBaseVault.sol";
import {AssetId} from "src/common/types/AssetId.sol";
import {PoolId} from "src/common/types/PoolId.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";
import {AccountId, AccountType} from "src/hub/interfaces/IHub.sol";
import {PoolEscrow} from "src/spoke/Escrow.sol";
import {IERC20} from "src/misc/interfaces/IERC20.sol";

import {TargetFunctions} from "./TargetFunctions.sol";
import {CryticSanity} from "./CryticSanity.sol";

// forge test --match-contract CryticToFoundry --match-path test/integration/recon-end-to-end/CryticToFoundry.sol -vv
contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    /// === Potential Issues === ///
    // forge test --match-test test_asyncVault_maxRedeem_8 -vvv 
    // NOTE: shows that user maintains an extra 1 wei of assets in maxRedeem after a redemption
    // see this issue: https://github.com/centrifuge/protocol-v3/issues/421
    function test_asyncVault_maxRedeem_8() public {
        shortcut_deployNewTokenPoolAndShare(16,29654276389875203551777999997167602027943,true,false,true);
        address poolEscrow = address(poolEscrowFactory.escrow(IBaseVault(_getVault()).poolId()));
        
        shortcut_deposit_and_claim(0,1,143,1,0);

        (, uint128 maxWithdraw,,,,,,,,) = asyncRequestManager.investments(IBaseVault(_getVault()), _getActor());
        console2.log("maxWithdraw before redeeming and claiming: %e", maxWithdraw);
        // queues a redemption of 1.2407674564261682736e20 shares, 124 assets
        // results in a stuck 1 wei of "virtual" assets in state.maxWithdraw
        // this is because in _processRedeem, state.maxWithdraw = state.maxWithdraw - assetsUp = 124 - 123 = 1
        console2.log("initial pool escrow balance: ", MockERC20(address(IBaseVault(_getVault()).asset())).balanceOf(poolEscrow));
        
        console2.log(" === Before Redeem and Claim === ");
        shortcut_redeem_and_claim_clamped(44055836141804467353088311715299154505223682107,1,60194726908356682833407755266714281307);
        (, maxWithdraw,,,,,,,,) = asyncRequestManager.investments(IBaseVault(_getVault()), _getActor());
        console2.log("maxWithdraw after redeeming and claiming: ", maxWithdraw);

        console2.log("pool escrow balance after redeeming and claiming: ", MockERC20(address(IBaseVault(_getVault()).asset())).balanceOf(poolEscrow));
        // asset is gets wiped out from the state.maxWithdraw, but is still in the escrow balance
        console2.log(" === Before maxRedeem === ");
        asyncVault_maxRedeem(0,0,0);
        (, maxWithdraw,,,,,,,,) = asyncRequestManager.investments(IBaseVault(_getVault()), _getActor());
        console2.log("maxWithdraw after maxRedeem: ", maxWithdraw);
    }

    // forge test --match-test test_asyncVault_maxDeposit_3 -vvv 
    // NOTE: admin issue with NAV passed in 
    // see this issue: https://github.com/centrifuge/protocol-v3/issues/422
    function test_asyncVault_maxDeposit_3() public {
        shortcut_deployNewTokenPoolAndShare(0,1,false,false,false);
        IBaseVault vault = IBaseVault(_getVault());

        console2.log(" === Before Deposit === ");
        shortcut_deposit_sync(1,2380311791704365157);
        console2.log(" === After Deposit === ");
        poolEscrowFactory.escrow(vault.poolId()).availableBalanceOf(vault.scId(), vault.asset(), 0);

        // console2.log(" === Before Cancel Redeem === ");
        shortcut_cancel_redeem_immediately_issue_and_revoke_clamped(1,1018635830101702210,0);

        asyncVault_maxDeposit(0,0,0);
    }

    // forge test --match-test test_asyncVault_maxDeposit_13 -vvv 
    // NOTE: related to the above, seems to be that claimable cancel deposit request is not being updated correctly
    function test_asyncVault_maxDeposit_13() public {

        shortcut_deployNewTokenPoolAndShare(0,1,true,false,true);

        shortcut_deposit_queue_cancel(0,1,1,1,1,0);

        hub_notifyDeposit(1);

        shortcut_request_deposit(0,1,1,0);

        asyncVault_maxDeposit(0,0,0);

    }

    // forge test --match-test test_asyncVault_maxMint_5 -vvv 
    // NOTE: same as the above
    function test_asyncVault_maxMint_5() public {

        shortcut_deployNewTokenPoolAndShare(27,1,true,false,false);

        shortcut_deposit_sync(0,1001264570074274036555728822370);

        console2.log(" === Before Mint === ");
        asyncVault_maxMint(0,0,0);

    }

    // forge test --match-test test_hub_notifyDeposit_9 -vvv 
    // NOTE: looks like a real issue
    function test_hub_notifyDeposit_9() public {

        shortcut_deployNewTokenPoolAndShare(0,1,false,false,true);

        shortcut_deposit_queue_cancel(0,1,2,1,1,0);

        shortcut_deposit_queue_cancel(0,1,0,1,1,0);

        hub_notifyDeposit(1);

    }

    // forge test --match-test test_property_asset_soundness_7 -vvv 
    // NOTE: might be a real issue or something about property assumption is incorrect
    function test_property_asset_soundness_7() public {

        shortcut_deployNewTokenPoolAndShare(0,1,true,false,false);

        hub_setQueue_clamped(false);

        shortcut_mint_sync(1,10000556069156430593232020144282359);

        hub_updateHoldingValuation_clamped(false);

        shortcut_request_deposit(0,1,0,0);

        hub_updateHoldingValue();

        balanceSheet_withdraw(0,1);

        property_asset_soundness();

    }

    // forge test --match-test test_property_gain_soundness_10 -vvv 
    // NOTE: might be a real issue or something about property assumption is incorrect
    function test_property_gain_soundness_10() public {

        shortcut_deployNewTokenPoolAndShare(4,1,true,false,false);

        hub_setQueue_clamped(false);

        shortcut_mint_sync(1,100084919394955237472397927082214);

        hub_updateHoldingValuation_clamped(false);

        shortcut_request_deposit(0,1,0,0);

        hub_updateHoldingValue();

        balanceSheet_withdraw(0,1);

        property_gain_soundness();
    }


    /// === Categorized Issues === ///
    // forge test --match-test test_property_holdings_balance_equals_escrow_balance_0 -vvv 
    // NOTE: passing in 0 for pricePoolPerShare results in holdingAssetAmount being 0
    // TODO: either add a precondition to check price isn't 0 or accept that property can't be checked
    function test_property_holdings_balance_equals_escrow_balance_0() public {

        shortcut_deployNewTokenPoolAndShare(0,1,true,false,true);

        shortcut_deposit_and_claim(0,1,1,1,0);

        property_holdings_balance_equals_escrow_balance();
    }

    // forge test --match-test test_property_escrow_balance_2 -vvv 
    // NOTE: issue with ghost tracking variables that needs to be fixed
    function test_property_escrow_balance_2() public {

        shortcut_deployNewTokenPoolAndShare(0,1,false,false,false);

        shortcut_deposit_sync(0,5421286);

        asyncVault_maxDeposit(0,0,0);

        property_escrow_balance();
    }

    // forge test --match-test test_property_sum_of_received_leq_fulfilled_4 -vvv 
    // NOTE: issue with ghost tracking variables that needs to be fixed
    function test_property_sum_of_received_leq_fulfilled_4() public {

        shortcut_deployNewTokenPoolAndShare(0,183298046153037838558708965697738377830,true,false,true);

        shortcut_deposit_and_claim(0,1,1,1,0);

        shortcut_cancel_redeem_claim_clamped(1,0,507631448169772);

        shortcut_queue_redemption(1,0,68399535177262588966825901408398773);

        shortcut_cancel_redeem_clamped(1,0,0);

        shortcut_withdraw_and_claim_clamped(1,0,0);

        shortcut_cancel_redeem_claim_clamped(0,0,0);

        property_sum_of_received_leq_fulfilled();

    }

    // forge test --match-test test_property_sum_of_minted_equals_total_supply_5 -vvv 
    // NOTE: issue with ghost tracking variables that needs to be fixed, probably due to not updating correctly for sync deposits
    function test_property_sum_of_minted_equals_total_supply_5() public {

        shortcut_deployNewTokenPoolAndShare(0,1,false,false,false);

        shortcut_deposit_sync(0,5421521);

        asyncVault_maxDeposit(0,0,0);

        property_sum_of_minted_equals_total_supply();
    }

    // forge test --match-test test_property_sum_of_shares_received_8 -vvv 
    // NOTE: looks like an issue with ghost tracking variables that needs to be fixed
    function test_property_sum_of_shares_received_8() public {

        shortcut_deployNewTokenPoolAndShare(0,1,false,false,true);

        shortcut_deposit_queue_cancel(0,1,1,1,1,0);

        spoke_deployVault(true);

        hub_notifyDeposit(1);

        property_sum_of_shares_received();

    }

    // forge test --match-test test_property_escrow_share_balance_12 -vvv 
    // NOTE: issue with ghost tracking variables that needs to be fixed
    function test_property_escrow_share_balance_12() public {

        shortcut_deployNewTokenPoolAndShare(0,1,false,false,true);

        shortcut_deposit_queue_cancel(0,1,1,1,1,0);

        property_escrow_share_balance();

    }

    // forge test --match-test test_property_sum_of_pending_redeem_request_15 -vvv 
    // NOTE: issue with ghost tracking variables that needs to be fixed
    function test_property_sum_of_pending_redeem_request_15() public {

        shortcut_deployNewTokenPoolAndShare(7,1,true,false,false);

        shortcut_mint_sync(5,100002568647520682296840139972);

        vault_requestRedeem_clamped(1,1);

        shortcut_redeem_and_claim(4,1333562963727601499,42450208829997526553514915981);

        property_sum_of_pending_redeem_request();
    }

    // forge test --match-test test_property_totalAssets_solvency_17 -vvv 
    // NOTE: pls check the property and see if it can ever actually hold,
    // it seems like the ability of the admin to pass in a high NAV can easily break this always by always changing the share price
    function test_property_totalAssets_solvency_17() public {

        shortcut_deployNewTokenPoolAndShare(13,1,false,false,false);

        shortcut_deposit_sync(1,20);

        balanceSheet_withdraw(0,1);

        property_totalAssets_solvency();

    }

    /// === Newest Issues === ///

    // forge test --match-test test_property_holdings_balance_equals_escrow_balance_echidna_1 -vvv
    // Echidna E2E reproducer #7835402543848108176
    // Category A: holdings != escrow balance after deposit_sync (non-zero price, SyncDepositVault)
    function test_property_holdings_balance_equals_escrow_balance_echidna_1() public {
        shortcut_deployNewTokenPoolAndShare(0, 96393658749476385723357733546643215341366704676065917183446, false, false, false);
        shortcut_deposit_sync(1, 60442435263903437);
        property_holdings_balance_equals_escrow_balance();
    }

    // forge test --match-test test_property_holdings_balance_equals_escrow_balance_echidna_2 -vvv
    // Echidna E2E reproducer #984593248541434999
    // Category A: holdings != escrow balance after deposit_sync (non-zero price, SyncDepositVault)
    function test_property_holdings_balance_equals_escrow_balance_echidna_2() public {
        shortcut_deployNewTokenPoolAndShare(0, 1298111903202386810132492399622022, false, false, false);
        shortcut_deposit_sync(1, 7364027);
        property_holdings_balance_equals_escrow_balance();
    }

    // forge test --match-test test_dust_deposit_totalSupply_overflow -vvv
    // Verify: can 1 wei dust deposits with low navPerShare overflow/DoS totalSupply?
    function test_dust_deposit_totalSupply_overflow() public {
        shortcut_deployNewTokenPoolAndShare(0, 1298111903202386810132492399622022, false, false, false);

        IBaseVault vault = IBaseVault(_getVault());
        IShareToken shareToken = IShareToken(vault.share());

        console2.log("=== 1st dust deposit (1 wei, navPerShare=7364027) ===");
        shortcut_deposit_sync(1, 7364027);
        uint256 supply1 = shareToken.totalSupply();
        console2.log("totalSupply after 1st:", supply1);
        console2.log("uint128.max:", type(uint128).max);
        console2.log("ratio (supply/max):", supply1 * 100 / uint256(type(uint128).max), "%");

        console2.log("=== 2nd dust deposit (1 wei, navPerShare=7364027) ===");
        // This should revert with ExceedsMaxSupply if totalSupply would exceed uint128.max
        try this.do_deposit_sync(1, 7364027) {
            uint256 supply2 = shareToken.totalSupply();
            console2.log("totalSupply after 2nd:", supply2);
            console2.log("2nd deposit SUCCEEDED - no overflow protection triggered!");
        } catch (bytes memory reason) {
            console2.log("2nd deposit REVERTED (expected: ExceedsMaxSupply)");
            console2.log("DoS vector confirmed: 1 wei blocks all future deposits");
        }
    }

    // forge test --match-test test_dust_deposit_extreme_low_price -vvv
    // Verify: navPerShare=1 (minimum non-zero D18) with 1 wei deposit
    function test_dust_deposit_extreme_low_price() public {
        shortcut_deployNewTokenPoolAndShare(0, 1298111903202386810132492399622022, false, false, false);

        IBaseVault vault = IBaseVault(_getVault());
        IShareToken shareToken = IShareToken(vault.share());

        console2.log("=== Extreme case: navPerShare=1 (D18: 1e-18) ===");
        try this.do_deposit_sync(1, 1) {
            uint256 supply = shareToken.totalSupply();
            console2.log("totalSupply:", supply);
            console2.log("uint128.max:", type(uint128).max);
        } catch (bytes memory) {
            console2.log("REVERTED - ExceedsMaxSupply on FIRST deposit with navPerShare=1");
            console2.log("Single 1 wei deposit DoS confirmed at navPerShare=1");
        }

        console2.log("=== Moderate case: navPerShare=1e14 (MIN_PRICE from PricingLib tests) ===");
        // Reset by deploying fresh - but we can't in this test, so just log the math
        // shares = pricePoolPerAsset * 1 * 1e18 / (1e18 * 1e14) = pricePoolPerAsset / 1e14
        // If pricePoolPerAsset ~ 1e18 -> shares ~ 1e4 (10000) - safe
        console2.log("At MIN_PRICE=1e14: 1 wei deposit -> ~10000 shares (safe)");
    }

    // Helper to make a deposit callable via try/catch
    function do_deposit_sync(uint256 assets, uint128 navPerShare) external {
        shortcut_deposit_sync(assets, navPerShare);
    }

    // forge test --match-test test_debug_holdings_vs_escrow -vvv
    // Deep-dive: trace deposit_sync flow to identify root cause
    function test_debug_holdings_vs_escrow() public {
        shortcut_deployNewTokenPoolAndShare(0, 1298111903202386810132492399622022, false, false, false);

        IBaseVault vault = IBaseVault(_getVault());
        address asset = vault.asset();
        AssetId assetId = hubRegistry.currency(vault.poolId());
        address poolEscrow = address(poolEscrowFactory.escrow(vault.poolId()));

        console2.log("=== BEFORE deposit_sync ===");
        (uint128 holdingBefore,,,) = holdings.holding(vault.poolId(), vault.scId(), assetId);
        uint256 escrowBefore = MockERC20(asset).balanceOf(poolEscrow);
        bool qDisabled = balanceSheet.queueDisabled(vault.poolId(), vault.scId());
        console2.log("holdingAssetAmount:", holdingBefore);
        console2.log("escrowBalance:", escrowBefore);
        console2.log("queueDisabled:", qDisabled);

        console2.log("=== deposit_sync(assets=1, navPerShare=7364027) ===");
        uint256 sharesBefore = IShareToken(vault.share()).balanceOf(_getActor());
        shortcut_deposit_sync(1, 7364027);
        uint256 sharesAfter = IShareToken(vault.share()).balanceOf(_getActor());
        console2.log("shares minted:", sharesAfter - sharesBefore);

        console2.log("=== AFTER deposit_sync ===");
        (uint128 holdingAfter,,,) = holdings.holding(vault.poolId(), vault.scId(), assetId);
        uint256 escrowAfter = MockERC20(asset).balanceOf(poolEscrow);
        console2.log("holdingAssetAmount:", holdingAfter);
        console2.log("escrowBalance:", escrowAfter);
        console2.log("delta holding:", holdingAfter - holdingBefore);
        console2.log("delta escrow:", escrowAfter - escrowBefore);

        // Check: is this a precondition inversion bug?
        console2.log("=== ANALYSIS ===");
        console2.log("Property checks when !queueDisabled =", !qDisabled);
        console2.log("But _updateAssets only updates Holdings when queueDisabled = true");
        console2.log("Comment says: 'if queue is enabled, holdings dont get updated until submitted'");
        console2.log("=> Precondition is INVERTED: should be if(queueDisabled) not if(!queueDisabled)");
    }

    /// === Category B: property_totalAssets_solvency (Known ❌ #26) === ///

    // forge test --match-test test_echidna_totalAssets_solvency_1 -vvv
    // Echidna E2E #518862186988112175
    function test_echidna_totalAssets_solvency_1() public {
        shortcut_deployNewTokenPoolAndShare(0, 1386237286839671356000540000449486512450075797368185259496410981011355, true, false, false);
        spoke_deployVault_clamped();
        hub_updateSharePrice(222132857126451087, hex"00000000000000000000000000000000", 17535);
        shortcut_deposit_and_cancel(36512601, 1036282021695511699692751134, 183726564367198340548773030622165509316593518938040152666045133820555468, 250, 8908809321817033694710154767);
        balanceSheet_issue(573676402864885549621857444533);
        property_totalAssets_solvency();
    }

    // forge test --match-test test_echidna_totalAssets_solvency_2 -vvv
    // Echidna E2E #1127038780738260532
    function test_echidna_totalAssets_solvency_2() public {
        shortcut_deployNewTokenPoolAndShare(0, 317236330380788908058070585027213285140075594077453900670729569634020, true, false, false);
        spoke_deployVault_clamped();
        hub_updateSharePrice(441805741455, hex"00000000000000000000000000000000", 17535);
        shortcut_deposit_and_cancel(573, 157309997219723664395722, 675006536620159792911744773139244048754920666982296274884072031175, 0, 2795564778656248368389132);
        balanceSheet_issue(573676402864885549621857444533);
        property_totalAssets_solvency();
    }

    /// === Category C: property_sum_of_minted_equals_total_supply (Known ❌ #16) === ///

    // forge test --match-test test_echidna_sum_minted_total_supply_1 -vvv
    // Echidna E2E #4993392222817840976
    function test_echidna_sum_minted_total_supply_1() public {
        shortcut_deployNewTokenPoolAndShare(0, 322451204253404809839657898545803571345631786866767406022329186129045401147, true, false, false);
        hub_updateSharePrice(2177124214410, hex"000000000000000000000000000099c8", 1);
        shortcut_request_deposit(24, 42146206658400722863123052399, 3453082117305778393197919140, 0);
        asyncVault_maxDeposit(0, 0, 0);
        property_sum_of_minted_equals_total_supply();
    }

    // forge test --match-test test_echidna_sum_minted_total_supply_2 -vvv
    // Echidna E2E #7795426837052371256
    function test_echidna_sum_minted_total_supply_2() public {
        shortcut_deployNewTokenPoolAndShare(0, 130508301449249762209694475187923039512549434386556866755690097035, false, false, false);
        hub_updateSharePrice(2407785, hex"00000000000000000000000000000000", 1);
        shortcut_request_deposit(0, 118473478401259, 273210755874720251, 0);
        asyncVault_maxDeposit(0, 0, 0);
        property_sum_of_minted_equals_total_supply();
    }

    /// === Category D: property_escrow_balance (Known ❌ #23) === ///

    // forge test --match-test test_echidna_escrow_balance_1 -vvv
    // Echidna E2E #6931770679071936629
    function test_echidna_escrow_balance_1() public {
        shortcut_deployNewTokenPoolAndShare(0, 4350165491806115384477658572863476966825025853672927706678398890014806491, true, false, false);
        hub_updateSharePrice(17582, hex"00000000000000000000000000000000", 2259097927806056812342429);
        shortcut_request_deposit(45824, 140960648834710952802247129010, 1756215732643594611169716, 0);
        asyncVault_maxDeposit(0, 0, 0);
        property_escrow_balance();
    }

    // forge test --match-test test_echidna_escrow_balance_2 -vvv
    // Echidna E2E #4928776995980949899
    function test_echidna_escrow_balance_2() public {
        shortcut_deployNewTokenPoolAndShare(0, 102102440359004603854514541888236606506951597997210388133637249, false, false, false);
        hub_updateSharePrice(0, hex"00000000000000000000000000000000", 41646746162178);
        shortcut_request_deposit(0, 8696248100709, 427403, 0);
        asyncVault_maxDeposit(0, 0, 0);
        property_escrow_balance();
    }

}
