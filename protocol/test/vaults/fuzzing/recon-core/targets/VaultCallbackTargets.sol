// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {vm} from "@chimera/Hevm.sol";
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {MockERC20} from "@recon/MockERC20.sol";

import {PoolId} from "src/core/types/PoolId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {D18} from "src/misc/types/D18.sol";
import {IBaseVault} from "src/vaults/interfaces/IBaseVault.sol";

import {Properties} from "../properties/Properties.sol";
import {OpType} from "../BeforeAfter.sol";

/// @dev Callback targets simulating hub→spoke fulfillment
abstract contract VaultCallbackTargets is BaseTargetFunctions, Properties {
    /// @dev Callback to fulfillDepositRequest
    function asyncRequests_fulfillDepositRequest(
        uint128 currencyPayout,
        uint128 tokenPayout,
        uint128 cancelledAssets,
        uint256 investorEntropy,
        D18 pricePoolPerShare
    ) public notGovFuzzing updateGhostsWithType(OpType.ADMIN) {
        address investor = _getRandomActor(investorEntropy);

        {
            (,,,, uint128 pendingDepositRequest,,,,,) =
                asyncRequestManager.investments(IBaseVault(address(vault)), investor);

            if (pendingDepositRequest == 0) return;
            currencyPayout %= pendingDepositRequest;
        }

        // 1. Issue share tokens to escrow via BalanceSheet (hub-side issuance)
        balanceSheet.issue(PoolId.wrap(poolId), ShareClassId.wrap(scId), address(escrow), tokenPayout);

        // 2. Fulfill the deposit request on ARM (updates investment state: maxMint, depositPrice)
        asyncRequestManager.fulfillDepositRequest(
            PoolId.wrap(poolId),
            ShareClassId.wrap(scId),
            investor,
            AssetId.wrap(assetId),
            currencyPayout,
            tokenPayout,
            cancelledAssets
        );

        // 3. Note the deposit on BalanceSheet (tracks asset amounts)
        {
            (address asset, uint256 tokenId) = spoke.idToAsset(AssetId.wrap(assetId));
            balanceSheet.noteDeposit(PoolId.wrap(poolId), ShareClassId.wrap(scId), asset, tokenId, currencyPayout);
        }

        // Ghost tracking
        sumOfFullfilledDeposits[address(token)] += tokenPayout;
        executedInvestments[address(token)] += tokenPayout;

        __globals();
    }

    /// @dev Callback to fulfillRedeemRequest
    function asyncRequests_fulfillRedeemRequest(
        uint128 currencyPayout,
        uint128 tokenPayout,
        uint128 cancelledShares,
        uint256 investorEntropy
    ) public notGovFuzzing updateGhostsWithType(OpType.ADMIN) {
        address investor = _getRandomActor(investorEntropy);

        {
            (,,,,, uint128 pendingRedeemRequest,,,,) =
                asyncRequestManager.investments(IBaseVault(address(vault)), investor);

            if (pendingRedeemRequest == 0) return;
            tokenPayout %= pendingRedeemRequest;
        }

        // 1. Deposit assets into PoolEscrow (simulating hub-side payout for redeemers)
        {
            (address asset, uint256 tokenId) = spoke.idToAsset(AssetId.wrap(assetId));
            address poolEscrowAddr = address(balanceSheet.escrow(PoolId.wrap(poolId)));
            MockERC20(asset).mint(poolEscrowAddr, currencyPayout);
            balanceSheet.noteDeposit(PoolId.wrap(poolId), ShareClassId.wrap(scId), asset, tokenId, currencyPayout);
        }
        mintedByCurrencyPayout[_getAsset()] += currencyPayout;

        // 2. revokedShares: reserves the deposited assets and revokes (burns) share tokens
        asyncRequestManager.revokedShares(
            PoolId.wrap(poolId),
            ShareClassId.wrap(scId),
            AssetId.wrap(assetId),
            currencyPayout,
            tokenPayout,
            D18.wrap(1e18)
        );

        // 3. Fulfill the redeem request on ARM
        asyncRequestManager.fulfillRedeemRequest(
            PoolId.wrap(poolId),
            ShareClassId.wrap(scId),
            investor,
            AssetId.wrap(assetId),
            currencyPayout,
            tokenPayout,
            cancelledShares
        );

        // Ghost tracking
        sumOfClaimedRequests[address(token)] += tokenPayout;
        executedRedemptions[address(token)] += tokenPayout;

        __globals();
    }
}
