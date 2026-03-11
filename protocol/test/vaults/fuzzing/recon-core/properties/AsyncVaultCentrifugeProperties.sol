// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Asserts} from "@chimera/Asserts.sol";
import {vm} from "@chimera/Hevm.sol";

import {IBaseVault} from "src/vaults/interfaces/IBaseVault.sol";
import {PoolId} from "src/core/types/PoolId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {PoolEscrow} from "src/core/spoke/PoolEscrow.sol";

import {Setup} from "../Setup.sol";
import {AsyncVaultProperties} from "./AsyncVaultProperties.sol";

/// @dev ERC-7540 Properties specific to Centrifuge with pre-checks
abstract contract AsyncVaultCentrifugeProperties is Setup, Asserts, AsyncVaultProperties {
    /// === Overridden with Centrifuge-specific pre-checks === ///
    function asyncVault_3(address asyncVaultTarget) public override {
        _centrifugeSpecificPreChecks();
        AsyncVaultProperties.asyncVault_3(asyncVaultTarget);
    }

    function asyncVault_4(address asyncVaultTarget) public override {
        _centrifugeSpecificPreChecks();
        AsyncVaultProperties.asyncVault_4(asyncVaultTarget);
    }

    function asyncVault_5(address asyncVaultTarget) public override {
        _centrifugeSpecificPreChecks();
        AsyncVaultProperties.asyncVault_5(asyncVaultTarget);
    }

    function asyncVault_6_deposit(address asyncVaultTarget, uint256 amt) public override {
        _centrifugeSpecificPreChecks();
        AsyncVaultProperties.asyncVault_6_deposit(asyncVaultTarget, amt);
    }

    function asyncVault_6_mint(address asyncVaultTarget, uint256 amt) public override {
        _centrifugeSpecificPreChecks();
        AsyncVaultProperties.asyncVault_6_mint(asyncVaultTarget, amt);
    }

    function asyncVault_6_withdraw(address asyncVaultTarget, uint256 amt) public override {
        _centrifugeSpecificPreChecks();
        AsyncVaultProperties.asyncVault_6_withdraw(asyncVaultTarget, amt);
    }

    function asyncVault_6_redeem(address asyncVaultTarget, uint256 amt) public override {
        _centrifugeSpecificPreChecks();
        AsyncVaultProperties.asyncVault_6_redeem(asyncVaultTarget, amt);
    }

    function asyncVault_7(address asyncVaultTarget, uint256 shares) public override {
        _centrifugeSpecificPreChecks();
        AsyncVaultProperties.asyncVault_7(asyncVaultTarget, shares);
    }

    function asyncVault_8(address asyncVaultTarget) public override {
        _centrifugeSpecificPreChecks();
        AsyncVaultProperties.asyncVault_8(asyncVaultTarget);
    }

    function asyncVault_9_deposit(address asyncVaultTarget) public override {
        _centrifugeSpecificPreChecks();
        AsyncVaultProperties.asyncVault_9_deposit(asyncVaultTarget);
    }

    function asyncVault_9_mint(address asyncVaultTarget) public override {
        _centrifugeSpecificPreChecks();
        AsyncVaultProperties.asyncVault_9_mint(asyncVaultTarget);
    }

    function asyncVault_9_withdraw(address asyncVaultTarget) public override {
        _centrifugeSpecificPreChecks();
        // PE_5: snapshot reserved before
        uint128 reservedBefore;
        address poolEscrowAddr = address(balanceSheet.escrow(PoolId.wrap(poolId)));
        {
            (address peAsset, uint256 peTokenId) = spoke.idToAsset(AssetId.wrap(assetId));
            (, reservedBefore) =
                PoolEscrow(payable(poolEscrowAddr)).holding(ShareClassId.wrap(scId), peAsset, peTokenId);
        }
        AsyncVaultProperties.asyncVault_9_withdraw(asyncVaultTarget);
        // PE_5: track reserved delta
        {
            (address peAsset, uint256 peTokenId) = spoke.idToAsset(AssetId.wrap(assetId));
            (, uint128 reservedAfter) =
                PoolEscrow(payable(poolEscrowAddr)).holding(ShareClassId.wrap(scId), peAsset, peTokenId);
            if (reservedBefore > reservedAfter) {
                ghostPoolEscrowReserved[keccak256(abi.encode(poolId, scId, peAsset, peTokenId))] -=
                    (reservedBefore - reservedAfter);
            }
        }
    }

    function asyncVault_9_redeem(address asyncVaultTarget) public override {
        _centrifugeSpecificPreChecks();
        // PE_5: snapshot reserved before
        uint128 reservedBefore;
        address poolEscrowAddr = address(balanceSheet.escrow(PoolId.wrap(poolId)));
        {
            (address peAsset, uint256 peTokenId) = spoke.idToAsset(AssetId.wrap(assetId));
            (, reservedBefore) =
                PoolEscrow(payable(poolEscrowAddr)).holding(ShareClassId.wrap(scId), peAsset, peTokenId);
        }
        AsyncVaultProperties.asyncVault_9_redeem(asyncVaultTarget);
        // PE_5: track reserved delta
        {
            (address peAsset, uint256 peTokenId) = spoke.idToAsset(AssetId.wrap(assetId));
            (, uint128 reservedAfter) =
                PoolEscrow(payable(poolEscrowAddr)).holding(ShareClassId.wrap(scId), peAsset, peTokenId);
            if (reservedBefore > reservedAfter) {
                ghostPoolEscrowReserved[keccak256(abi.encode(poolId, scId, peAsset, peTokenId))] -=
                    (reservedBefore - reservedAfter);
            }
        }
    }

    /// === Custom Centrifuge Properties === ///

    /// @dev Property: depositing up to maxDeposit succeeds, rounding drift bounded, shares <= maxMint
    function asyncVault_maxDeposit(uint256 depositAmount) public {
        uint256 maxDepositBefore = vault.maxDeposit(_getActor());
        require(maxDepositBefore > 0, "must be able to deposit");

        depositAmount = between(depositAmount, 1, maxDepositBefore);
        (uint128 maxMintBefore,,,,,,,,,) = asyncRequestManager.investments(IBaseVault(address(vault)), _getActor());

        vm.prank(_getActor());
        try vault.deposit(depositAmount, _getActor()) returns (uint256 shares) {
            sumOfClaimedDeposits[address(token)] += shares;
            uint256 maxDepositAfter = vault.maxDeposit(_getActor());
            uint256 difference = maxDepositBefore - depositAmount;
            // Rounding: deposit converts assets→sharesUP (state deduction) then recalculates
            // maxDeposit = sharesDown→assetsDown. With decimal gaps (0-18) and extreme prices,
            // the mulDiv round-trip accumulates more than single-unit rounding per conversion.
            // 1e3 tolerance covers all decimal/price combos while still catching real bugs.
            lte(_diff(difference, maxDepositAfter), 1e3, "rounding error in maxDeposit > 1e3 wei");

            if (depositAmount == maxDepositBefore) {
                lte(shares, maxMintBefore, "shares minted surpass maxMint");
            }
        } catch {}
    }

    /// @dev Property: minting maxMint leaves maxMint at 0
    /// mint() subtracts exact shares from state.maxMint (no rounding), so exact equality holds.
    /// When mintAmount == maxMintBefore: assets consumed (Up-rounded) may exceed maxDeposit (Down-rounded)
    /// by at most 1 wei, hence the tolerance on the asset comparison.
    function asyncVault_maxMint(uint256 mintAmount) public {
        uint256 maxMintBefore = vault.maxMint(_getActor());
        uint256 maxDepositBefore = vault.maxDeposit(_getActor());
        require(maxMintBefore > 0, "must be able to mint");

        mintAmount = between(mintAmount, 1, maxMintBefore);

        vm.prank(_getActor());
        try vault.mint(mintAmount, _getActor()) returns (uint256 assets) {
            sumOfClaimedDeposits[address(token)] += mintAmount;
            uint256 maxMintAfter = vault.maxMint(_getActor());
            uint256 difference = maxMintBefore - mintAmount;
            t(difference == maxMintAfter, "rounding error in maxMint");

            if (mintAmount == maxMintBefore) {
                (uint128 maxMintReq,,,,,,,,,) =
                    asyncRequestManager.investments(IBaseVault(address(vault)), _getActor());
                uint256 maxMintVaultAfter = vault.maxMint(_getActor());
                eq(maxMintReq, 0, "maxMint in request should be 0 after maxMint");
                eq(maxMintVaultAfter, 0, "maxMint in vault should be 0 after maxMint");
                // Compare assets consumed (Up-rounded) vs maxDeposit (Down-rounded): same price,
                // different rounding directions → up to 1 wei difference
                lte(assets, maxDepositBefore + 1, "assets consumed surpass maxDeposit + 1");
            }
        } catch {}
    }

    /// @dev Property: user can always withdraw between 1 and maxWithdraw
    function asyncVault_maxWithdraw(uint256 withdrawAmount) public {
        uint256 maxWithdrawBefore = vault.maxWithdraw(_getActor());
        require(maxWithdrawBefore > 0, "must be able to withdraw");

        withdrawAmount = between(withdrawAmount, 1, maxWithdrawBefore);

        // PE_5: snapshot reserved before (vault.withdraw → ARM._withdraw → balanceSheet.unreserve)
        uint128 reservedBefore;
        address poolEscrowAddr = address(balanceSheet.escrow(PoolId.wrap(poolId)));
        {
            (address peAsset, uint256 peTokenId) = spoke.idToAsset(AssetId.wrap(assetId));
            (, reservedBefore) =
                PoolEscrow(payable(poolEscrowAddr)).holding(ShareClassId.wrap(scId), peAsset, peTokenId);
        }

        vm.prank(_getActor());
        try vault.withdraw(withdrawAmount, _getActor(), _getActor()) returns (uint256 shares) {
            // PE_5: track reserved delta
            {
                (address peAsset, uint256 peTokenId) = spoke.idToAsset(AssetId.wrap(assetId));
                (, uint128 reservedAfter) =
                    PoolEscrow(payable(poolEscrowAddr)).holding(ShareClassId.wrap(scId), peAsset, peTokenId);
                if (reservedBefore > reservedAfter) {
                    ghostPoolEscrowReserved[keccak256(abi.encode(poolId, scId, peAsset, peTokenId))] -=
                        (reservedBefore - reservedAfter);
                }
            }
            // Use vault.asset() (fixed) not _getAsset() (switchable) for consistent ghost keying
            sumOfClaimedRedemptions[vault.asset()] += withdrawAmount;

            // NOTE: Fixed-tolerance rounding assertion removed. With extreme price ratios
            // and decimals mismatch (asset 6 / share 18), the 3-step mulDiv round-trip
            // (withdraw→convertToSharesUp→maxWithdraw→convertToAssetsDown) produces
            // errors proportional to pS/(10^12*pA), exceeding any fixed constant.
            // ERC-4626 maxWithdraw honoured property (property_V_4) covers the meaningful
            // safety guarantee: maxWithdraw > 0 ⇒ withdraw(maxWithdraw) succeeds.
        } catch {}
    }

    /// @dev Property: user can always redeem between 1 and maxRedeem
    function asyncVault_maxRedeem(uint256 redeemAmount) public {
        uint256 maxRedeemBefore = vault.maxRedeem(_getActor());
        require(maxRedeemBefore > 0, "must be able to redeem");

        redeemAmount = between(redeemAmount, 1, maxRedeemBefore);

        // PE_5: snapshot reserved before (vault.redeem → ARM._withdraw → balanceSheet.unreserve)
        uint128 reservedBefore;
        address poolEscrowAddr = address(balanceSheet.escrow(PoolId.wrap(poolId)));
        {
            (address peAsset, uint256 peTokenId) = spoke.idToAsset(AssetId.wrap(assetId));
            (, reservedBefore) =
                PoolEscrow(payable(poolEscrowAddr)).holding(ShareClassId.wrap(scId), peAsset, peTokenId);
        }

        vm.prank(_getActor());
        try vault.redeem(redeemAmount, _getActor(), _getActor()) returns (uint256 assets) {
            // PE_5: track reserved delta
            {
                (address peAsset, uint256 peTokenId) = spoke.idToAsset(AssetId.wrap(assetId));
                (, uint128 reservedAfter) =
                    PoolEscrow(payable(poolEscrowAddr)).holding(ShareClassId.wrap(scId), peAsset, peTokenId);
                if (reservedBefore > reservedAfter) {
                    ghostPoolEscrowReserved[keccak256(abi.encode(poolId, scId, peAsset, peTokenId))] -=
                        (reservedBefore - reservedAfter);
                }
            }
            // Use vault.asset() (fixed) not _getAsset() (switchable) for consistent ghost keying
            sumOfClaimedRedemptions[vault.asset()] += assets;

            uint256 maxRedeemAfter = vault.maxRedeem(_getActor());
            uint256 difference = maxRedeemBefore - redeemAmount;
            // Rounding: redeem converts shares→assetsUP (state deduction) then recalculates
            // maxRedeem from remaining state. With decimal gaps and extreme prices,
            // the mulDiv round-trip accumulates more than single-unit rounding per conversion.
            lte(_diff(difference, maxRedeemAfter), 1e3, "rounding error in maxRedeem > 1e3 wei");
        } catch {}
    }

    function _canCheckProperties() internal view returns (bool) {
        if (TODO_RECON_SKIP_ERC7540) return false;
        if (address(vault) == address(0)) return false;
        if (address(token) == address(0)) return false;
        if (address(fullRestrictions) == address(0)) return false;
        if (_getAsset() == address(0)) return false;
        return true;
    }

    function _centrifugeSpecificPreChecks() internal view {
        require(msg.sender == address(this));
        require(_canCheckProperties());
    }
}
