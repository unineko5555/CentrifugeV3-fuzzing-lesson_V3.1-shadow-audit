// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";
import {MockERC20} from "@recon/MockERC20.sol";

import {AsyncVault} from "src/vaults/AsyncVault.sol";
import {PoolId} from "src/core/types/PoolId.sol";

import {Properties} from "../properties/Properties.sol";

/// @dev Core vault interaction targets: ERC-7540/7887 user operations
abstract contract VaultTargets is BaseTargetFunctions, Properties {
    function _getTokenAndBalanceForVault() internal view returns (uint256) {
        return MockERC20(_getAsset()).balanceOf(_getActor());
    }

    // === REQUEST === //

    function vault_requestDeposit(uint256 assets, uint256 toEntropy) public updateGhosts {
        assets = between(assets, 0, _getTokenAndBalanceForVault());

        vm.prank(_getActor());
        MockERC20(_getAsset()).approve(address(vault), assets);
        address to = _getRandomActor(toEntropy);

        uint256 balanceB4 = MockERC20(_getAsset()).balanceOf(_getActor());
        uint256 balanceOfEscrowB4 = MockERC20(_getAsset()).balanceOf(address(escrow));

        bool hasReverted;
        vm.prank(_getActor());
        try vault.requestDeposit(assets, to, _getActor()) {
            sumOfDepositRequests[address(_getAsset())] += assets;
            requestDepositAssets[_getActor()][address(_getAsset())] += assets;
        } catch {
            hasReverted = true;
        }

        (bool isMember,) = fullRestrictions.isMember(address(token), _getActor());
        if (!isMember) {
            t(hasReverted, "LP-1 Must Revert");
        }
        if (
            fullRestrictions.isFrozen(address(token), _getActor()) == true
                || fullRestrictions.isFrozen(address(token), to) == true
        ) {
            t(hasReverted, "LP-2 Must Revert");
        }

        uint256 balanceAfter = MockERC20(_getAsset()).balanceOf(_getActor());
        uint256 balanceOfEscrowAfter = MockERC20(_getAsset()).balanceOf(address(escrow));

        if (!hasReverted) {
            uint256 deltaUser = balanceB4 - balanceAfter;
            uint256 deltaEscrow = balanceOfEscrowAfter - balanceOfEscrowB4;
            if (RECON_EXACT_BAL_CHECK) {
                eq(deltaUser, assets, "Extra LP-1");
            }
            eq(deltaUser, deltaEscrow, "7540-11");
        }
    }

    function vault_requestRedeem(uint256 shares, uint256 toEntropy) public updateGhosts {
        address to = _getRandomActor(toEntropy);

        uint256 balanceB4 = token.balanceOf(_getActor());
        uint256 balanceOfEscrowB4 = token.balanceOf(address(escrow));

        vm.prank(_getActor());
        token.approve(address(vault), shares);

        bool hasReverted;
        vm.prank(_getActor());
        try vault.requestRedeem(shares, to, _getActor()) {
            sumOfRedeemRequests[address(token)] += shares;
            requestRedeemShares[_getActor()][address(token)] += shares;
        } catch {
            hasReverted = true;
        }

        if (
            fullRestrictions.isFrozen(address(token), _getActor()) == true
                || fullRestrictions.isFrozen(address(token), to) == true
        ) {
            t(hasReverted, "LP-2 Must Revert");
        }

        uint256 balanceAfter = token.balanceOf(_getActor());
        uint256 balanceOfEscrowAfter = token.balanceOf(address(escrow));

        if (!hasReverted) {
            unchecked {
                uint256 deltaUser = balanceB4 - balanceAfter;
                uint256 deltaEscrow = balanceOfEscrowAfter - balanceOfEscrowB4;
                if (RECON_EXACT_BAL_CHECK) {
                    eq(deltaUser, shares, "Extra LP-1");
                }
                eq(deltaUser, deltaEscrow, "7540-12");
            }
        }
    }

    // === CANCEL === //

    function vault_cancelDepositRequest() public updateGhosts asActor {
        vault.cancelDepositRequest(REQUEST_ID, _getActor());
    }

    function vault_cancelRedeemRequest() public updateGhosts asActor {
        vault.cancelRedeemRequest(REQUEST_ID, _getActor());
    }

    function vault_claimCancelDepositRequest(uint256 toEntropy) public updateGhosts asActor {
        address to = _getRandomActor(toEntropy);
        uint256 assets = vault.claimCancelDepositRequest(REQUEST_ID, to, _getActor());
        sumOfClaimedDepositCancelations[address(_getAsset())] += assets;
    }

    function vault_claimCancelRedeemRequest(uint256 toEntropy) public updateGhosts asActor {
        address to = _getRandomActor(toEntropy);
        uint256 shares = vault.claimCancelRedeemRequest(REQUEST_ID, to, _getActor());
        sumOfClaimedRedeemCancelations[address(token)] += shares;
    }

    // === CLAIM === //

    function vault_deposit(uint256 assets) public updateGhosts {
        uint256 shareUserB4 = token.balanceOf(_getActor());
        uint256 shareEscrowB4 = token.balanceOf(address(escrow));

        vm.prank(_getActor());
        uint256 shares = vault.deposit(assets, _getActor());

        sumOfClaimedDeposits[address(token)] += shares;

        uint256 shareUserAfter = token.balanceOf(_getActor());
        uint256 shareEscrowAfter = token.balanceOf(address(escrow));

        unchecked {
            uint256 deltaUser = shareUserAfter - shareUserB4;
            uint256 deltaEscrow = shareEscrowB4 - shareEscrowAfter;
            if (RECON_EXACT_BAL_CHECK) {
                eq(deltaUser, assets, "Extra LP-2");
            }
            eq(deltaUser, deltaEscrow, "7540-13");
        }
    }

    function vault_mint(uint256 shares, uint256 toEntropy) public updateGhosts {
        address to = _getRandomActor(toEntropy);
        uint256 shareUserB4 = token.balanceOf(_getActor());
        uint256 shareEscrowB4 = token.balanceOf(address(escrow));

        vm.prank(_getActor());
        vault.mint(shares, to);

        sumOfClaimedDeposits[address(token)] += shares;

        uint256 shareUserAfter = token.balanceOf(_getActor());
        uint256 shareEscrowAfter = token.balanceOf(address(escrow));

        unchecked {
            uint256 deltaUser = shareUserAfter - shareUserB4;
            uint256 deltaEscrow = shareEscrowB4 - shareEscrowAfter;
            if (RECON_EXACT_BAL_CHECK) {
                eq(deltaUser, shares, "Extra LP-2");
            }
            eq(deltaUser, deltaEscrow, "7540-13");
        }
    }

    function vault_redeem(uint256 shares, uint256 toEntropy) public updateGhosts {
        address to = _getRandomActor(toEntropy);
        address poolEscrowAddr = address(balanceSheet.escrow(PoolId.wrap(poolId)));
        uint256 tokenUserB4 = MockERC20(_getAsset()).balanceOf(_getActor());
        uint256 tokenEscrowB4 = MockERC20(_getAsset()).balanceOf(poolEscrowAddr);

        vm.prank(_getActor());
        uint256 assets = vault.redeem(shares, to, _getActor());

        sumOfClaimedRedemptions[address(_getAsset())] += assets;

        uint256 tokenUserAfter = MockERC20(_getAsset()).balanceOf(_getActor());
        uint256 tokenEscrowAfter = MockERC20(_getAsset()).balanceOf(poolEscrowAddr);

        unchecked {
            uint256 deltaUser = tokenUserAfter - tokenUserB4;
            eq(deltaUser, assets, "FoT-1");
            uint256 deltaEscrow = tokenEscrowB4 - tokenEscrowAfter;
            if (RECON_EXACT_BAL_CHECK) {
                eq(deltaUser, shares, "Extra LP-3");
            }
            eq(deltaUser, deltaEscrow, "7540-14");
        }
    }

    function vault_withdraw(uint256 assets, uint256 toEntropy) public updateGhosts {
        address to = _getRandomActor(toEntropy);
        address poolEscrowAddr = address(balanceSheet.escrow(PoolId.wrap(poolId)));
        uint256 tokenUserB4 = MockERC20(_getAsset()).balanceOf(_getActor());
        uint256 tokenEscrowB4 = MockERC20(_getAsset()).balanceOf(poolEscrowAddr);

        vm.prank(_getActor());
        vault.withdraw(assets, to, _getActor());

        sumOfClaimedRedemptions[address(_getAsset())] += assets;

        uint256 tokenUserAfter = MockERC20(_getAsset()).balanceOf(_getActor());
        uint256 tokenEscrowAfter = MockERC20(_getAsset()).balanceOf(poolEscrowAddr);

        unchecked {
            uint256 deltaUser = tokenUserAfter - tokenUserB4;
            uint256 deltaEscrow = tokenEscrowB4 - tokenEscrowAfter;
            if (RECON_EXACT_BAL_CHECK) {
                eq(deltaUser, assets, "Extra LP-3");
            }
            eq(deltaUser, deltaEscrow, "7540-14");
        }
    }
}
