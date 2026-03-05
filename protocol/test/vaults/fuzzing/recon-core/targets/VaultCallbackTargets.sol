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
            // Clamp cancelledAssets: currencyPayout + cancelledAssets <= pendingDepositRequest
            uint128 remaining = pendingDepositRequest - currencyPayout;
            cancelledAssets = uint128(uint256(cancelledAssets) % (uint256(remaining) + 1));
        }

        // Compute tokenPayout from live spoke prices (mirrors real Hub behavior).
        // In the real protocol, the Hub computes shares from the epoch price.
        // Without this, unclamped tokenPayout creates extreme depositPrice ratios
        // (weighted average in ARM), causing rounding errors >> 50 wei in max* properties.
        if (currencyPayout > 0) {
            try vault.convertToShares(currencyPayout) returns (uint256 computedShares) {
                if (computedShares > 0) tokenPayout = uint128(computedShares);
            } catch {}
        }
        // Fallback: if convertToShares returned 0 (pricePoolPerShare=0) or reverted,
        // clamp ratio both directions to keep rounding error ≤ 50 wei.
        // Upper bound (depositPrice ≤ 50e18): error in maxDeposit = P/1e18 ≤ 50
        // Lower bound (depositPrice ≥ 2e16): error in maxMint = 1e18/P ≤ 50
        if (currencyPayout > 0 && tokenPayout > 0) {
            if (uint256(currencyPayout) / uint256(tokenPayout) > 50) {
                tokenPayout = uint128(uint256(currencyPayout) / 50);
            } else if (uint256(tokenPayout) / uint256(currencyPayout) > 50) {
                tokenPayout = uint128(uint256(currencyPayout) * 50);
            }
        }
        if (tokenPayout == 0) tokenPayout = 1;

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

        // 3. Note deposit + transfer globalEscrow → poolEscrow (matches real approvedDeposits flow)
        // Both noteDeposit AND transfer are conditional: noteDeposit increases PoolEscrow.holding.total,
        // so only call it when we also transfer actual tokens (PE_2: ERC20 balance >= holding.total)
        {
            (address asset, uint256 tokenId) = spoke.idToAsset(AssetId.wrap(assetId));
            address poolEscrowAddr = address(balanceSheet.escrow(PoolId.wrap(poolId)));
            if (currencyPayout > 0 && MockERC20(asset).balanceOf(address(escrow)) >= currencyPayout) {
                balanceSheet.noteDeposit(PoolId.wrap(poolId), ShareClassId.wrap(scId), asset, tokenId, currencyPayout);
                escrow.authTransferTo(asset, tokenId, poolEscrowAddr, currencyPayout);
                sumOfTransfersOut[asset] += currencyPayout;
                mintedByCurrencyPayout[asset] += currencyPayout;
            }
        }

        // Ghost tracking
        sumOfFullfilledDeposits[address(token)] += tokenPayout;
        executedInvestments[address(token)] += tokenPayout;
        if (cancelledAssets > 0) {
            // Use vault.asset() (fixed) not _getAsset() (switchable) for consistent ghost keying
            cancelDepositCurrencyPayout[vault.asset()] += cancelledAssets;
        }

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
            // Clamp cancelledShares: tokenPayout + cancelledShares <= pendingRedeemRequest
            uint128 remaining = pendingRedeemRequest - tokenPayout;
            cancelledShares = uint128(uint256(cancelledShares) % (uint256(remaining) + 1));
        }

        // Compute currencyPayout from live spoke prices (mirrors real Hub behavior).
        // In the real protocol, the Hub computes assets from the epoch price.
        // Without this, unclamped currencyPayout creates extreme redeemPrice ratios
        // (weighted average in ARM), causing rounding errors >> 50 wei in max* properties.
        if (tokenPayout > 0) {
            try vault.convertToAssets(tokenPayout) returns (uint256 computedAssets) {
                if (computedAssets > 0) currencyPayout = uint128(computedAssets);
            } catch {}
        }
        // Fallback: if convertToAssets returned 0 (pricePoolPerAsset=0) or reverted,
        // clamp ratio both directions to keep rounding error ≤ 50 wei.
        // Upper bound (redeemPrice ≤ 50e18): error in maxWithdraw = P/1e18 ≤ 50
        // Lower bound (redeemPrice ≥ 2e16): error in maxRedeem = 1e18/P ≤ 50
        if (tokenPayout > 0 && currencyPayout > 0) {
            if (uint256(currencyPayout) / uint256(tokenPayout) > 50) {
                currencyPayout = uint128(uint256(tokenPayout) * 50);
            } else if (uint256(tokenPayout) / uint256(currencyPayout) > 50) {
                currencyPayout = uint128(uint256(tokenPayout) / 50);
                if (currencyPayout == 0) currencyPayout = 1;
            }
        }
        if (currencyPayout == 0) currencyPayout = 1;

        // 1. Deposit assets into PoolEscrow (simulating hub-side payout for redeemers)
        {
            (address asset, uint256 tokenId) = spoke.idToAsset(AssetId.wrap(assetId));
            address poolEscrowAddr = address(balanceSheet.escrow(PoolId.wrap(poolId)));
            MockERC20(asset).mint(poolEscrowAddr, currencyPayout);
            balanceSheet.noteDeposit(PoolId.wrap(poolId), ShareClassId.wrap(scId), asset, tokenId, currencyPayout);
        }
        {
            (address asset_,) = spoke.idToAsset(AssetId.wrap(assetId));
            mintedByCurrencyPayout[asset_] += currencyPayout;
        }

        // 2. revokedShares: reserves the deposited assets and revokes (burns) share tokens
        asyncRequestManager.revokedShares(
            PoolId.wrap(poolId),
            ShareClassId.wrap(scId),
            AssetId.wrap(assetId),
            currencyPayout,
            tokenPayout,
            D18.wrap(1e18)
        );

        // Ghost: revokedShares reserves assets in PoolEscrow (PE_5)
        {
            (address asset_, uint256 tokenId_) = spoke.idToAsset(AssetId.wrap(assetId));
            ghostPoolEscrowReserved[keccak256(abi.encode(poolId, scId, asset_, tokenId_))] += currencyPayout;
        }

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
        if (cancelledShares > 0) {
            cancelRedeemShareTokenPayout[address(token)] += cancelledShares;
        }

        __globals();
    }

    /// @dev ARM batch-level: approve deposits (moves assets globalEscrow → poolEscrow)
    function arm_approvedDeposits(uint128 assetAmount, uint128 price)
        public
        notGovFuzzing
        updateGhostsWithType(OpType.ADMIN)
    {
        (address asset,) = spoke.idToAsset(AssetId.wrap(assetId));
        uint256 available = MockERC20(asset).balanceOf(address(escrow));
        if (available == 0) return;
        assetAmount = uint128(uint256(assetAmount) % available);
        if (assetAmount == 0) assetAmount = 1;
        price = uint128(uint256(price) % 1000e18) + 1e15;

        try asyncRequestManager.approvedDeposits(
            PoolId.wrap(poolId),
            ShareClassId.wrap(scId),
            AssetId.wrap(assetId),
            assetAmount,
            D18.wrap(price)
        ) {
            sumOfTransfersOut[asset] += assetAmount;
            mintedByCurrencyPayout[asset] += assetAmount;
        } catch {}
    }

    /// @dev ARM batch-level: issue shares (mints shares to globalEscrow)
    function arm_issuedShares(uint128 shareAmount, uint128 price)
        public
        notGovFuzzing
        updateGhostsWithType(OpType.ADMIN)
    {
        shareAmount = uint128(uint256(shareAmount) % 1_000_000e18) + 1;
        price = uint128(uint256(price) % 1000e18) + 1e15;

        try asyncRequestManager.issuedShares(
            PoolId.wrap(poolId), ShareClassId.wrap(scId), shareAmount, D18.wrap(price)
        ) {
            sumOfFullfilledDeposits[address(token)] += shareAmount;
            shareMints[address(token)] += shareAmount;
        } catch {}
    }

    // === ARM Subsidy Targets (coverage improvement) === //

    /// @dev Deposit ETH subsidy to RefundEscrow for gas cost prepayment
    function arm_depositSubsidy() public payable {
        uint256 value = address(this).balance > 0 ? address(this).balance % 1 ether : 0;
        if (value == 0) return;
        try asyncRequestManager.depositSubsidy{value: value}(PoolId.wrap(poolId)) {} catch {}
    }

    /// @dev Withdraw ETH subsidy from RefundEscrow (auth required — deployer is warded)
    function arm_withdrawSubsidy(uint256 amount) public asAdmin {
        try asyncRequestManager.withdrawSubsidy(PoolId.wrap(poolId), _getActor(), amount) {} catch {}
    }
}
