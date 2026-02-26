// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Asserts} from "@chimera/Asserts.sol";
import {vm} from "@chimera/Hevm.sol";

import {IBaseVault} from "src/vaults/interfaces/IBaseVault.sol";

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
        AsyncVaultProperties.asyncVault_9_withdraw(asyncVaultTarget);
    }

    function asyncVault_9_redeem(address asyncVaultTarget) public override {
        _centrifugeSpecificPreChecks();
        AsyncVaultProperties.asyncVault_9_redeem(asyncVaultTarget);
    }

    /// === Custom Centrifuge Properties === ///

    /// @dev Property: depositing maxDeposit leaves 0 pending orders, doesn't mint more than maxMint
    function asyncVault_maxDeposit(uint256 depositAmount) public {
        uint256 maxDepositBefore = vault.maxDeposit(_getActor());
        require(maxDepositBefore > 0, "must be able to deposit");

        depositAmount = between(depositAmount, 1, maxDepositBefore);
        (uint128 maxMint,,,,,,,,,) = asyncRequestManager.investments(IBaseVault(address(vault)), _getActor());

        vm.prank(_getActor());
        try vault.deposit(depositAmount, _getActor()) returns (uint256 shares) {
            uint256 maxDepositAfter = vault.maxDeposit(_getActor());
            uint256 difference = maxDepositBefore - depositAmount;
            t(difference == maxDepositAfter, "rounding error in maxDeposit");

            if (depositAmount == maxDepositBefore) {
                (,,,, uint128 pendingDeposit,,,,,) =
                    asyncRequestManager.investments(IBaseVault(address(vault)), _getActor());
                eq(pendingDeposit, 0, "pendingDeposit should be 0 after maxDeposit");
                lte(shares, maxMint, "shares minted surpass maxMint");
            }
        } catch {}
    }

    /// @dev Property: minting maxMint leaves maxMint at 0
    function asyncVault_maxMint(uint256 mintAmount) public {
        uint256 maxMintBefore = vault.maxMint(_getActor());
        uint256 maxDepositBefore = vault.maxDeposit(_getActor());
        require(maxMintBefore > 0, "must be able to mint");

        mintAmount = between(mintAmount, 1, maxMintBefore);

        vm.prank(_getActor());
        try vault.mint(mintAmount, _getActor()) returns (uint256 assets) {
            uint256 maxMintAfter = vault.maxMint(_getActor());
            uint256 difference = maxMintBefore - mintAmount;
            t(difference == maxMintAfter, "rounding error in maxMint");
            uint256 shares = vault.convertToShares(assets);

            if (mintAmount == maxMintBefore) {
                (uint128 maxMintReq,,,,,,,,,) =
                    asyncRequestManager.investments(IBaseVault(address(vault)), _getActor());
                uint256 maxMintVaultAfter = vault.maxMint(_getActor());
                eq(maxMintReq, 0, "maxMint in request should be 0 after maxMint");
                eq(maxMintVaultAfter, 0, "maxMint in vault should be 0 after maxMint");
                lte(shares, maxDepositBefore, "shares minted surpass maxDeposit");
            }
        } catch {}
    }

    /// @dev Property: user can always withdraw between 1 and maxWithdraw
    function asyncVault_maxWithdraw(uint256 withdrawAmount) public {
        uint256 maxWithdrawBefore = vault.maxWithdraw(_getActor());
        require(maxWithdrawBefore > 0, "must be able to withdraw");

        withdrawAmount = between(withdrawAmount, 1, maxWithdrawBefore);

        vm.prank(_getActor());
        try vault.withdraw(withdrawAmount, _getActor(), _getActor()) returns (uint256 shares) {
            uint256 maxWithdrawAfter = vault.maxWithdraw(_getActor());
            uint256 difference = maxWithdrawBefore - withdrawAmount;
            uint256 assets = vault.convertToAssets(shares);
            t(difference == maxWithdrawAfter, "rounding error in maxWithdraw");

            if (withdrawAmount == maxWithdrawBefore) {
                (,,,,, uint128 pendingWithdrawRequest,,,,) =
                    asyncRequestManager.investments(IBaseVault(address(vault)), _getActor());
                eq(pendingWithdrawRequest, 0, "pendingWithdrawRequest should be 0 after maxWithdraw");
                lte(assets, maxWithdrawBefore, "assets withdrawn surpass maxWithdraw");
            }
        } catch {}
    }

    /// @dev Property: user can always redeem between 1 and maxRedeem
    function asyncVault_maxRedeem(uint256 redeemAmount) public {
        uint256 maxRedeemBefore = vault.maxRedeem(_getActor());
        require(maxRedeemBefore > 0, "must be able to redeem");

        redeemAmount = between(redeemAmount, 1, maxRedeemBefore);

        vm.prank(_getActor());
        try vault.redeem(redeemAmount, _getActor(), _getActor()) returns (uint256 assets) {
            uint256 maxRedeemAfter = vault.maxRedeem(_getActor());
            uint256 difference = maxRedeemBefore - redeemAmount;
            uint256 shares = vault.convertToShares(assets);
            t(difference == maxRedeemAfter, "rounding error in maxRedeem");

            if (redeemAmount == maxRedeemBefore) {
                (,,,,, uint128 pendingRedeemRequest,,,,) =
                    asyncRequestManager.investments(IBaseVault(address(vault)), _getActor());
                eq(pendingRedeemRequest, 0, "pendingRedeemRequest should be 0 after maxRedeem");
                lte(shares, maxRedeemBefore, "shares redeemed surpass maxRedeem");
            }
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
