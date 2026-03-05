// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";
import {MockERC20} from "@recon/MockERC20.sol";

import {AsyncVault} from "src/vaults/AsyncVault.sol";
import {PoolId} from "src/core/types/PoolId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {PoolEscrow} from "src/core/spoke/PoolEscrow.sol";

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
            // Use vault.asset() (fixed) not _getAsset() (switchable) for consistent ghost keying
            sumOfDepositRequests[vault.asset()] += assets;
            requestDepositAssets[_getActor()][vault.asset()] += assets;
        } catch {
            hasReverted = true;
        }

        // LP-1: Non-member must revert (only under FullRestrictions; endorsement bypasses membership)
        if (address(token.hook()) == address(fullRestrictions)) {
            (bool isMember,) = fullRestrictions.isMember(address(token), _getActor());
            if (!isMember && !root.endorsed(_getActor())) {
                t(hasReverted, "LP-1 Must Revert");
            }
        }
        // LP-2: Frozen must revert — only under FullRestrictions.
        // Endorsed addresses (including CryticTester) bypass frozen check in the hook.
        if (
            address(token.hook()) == address(fullRestrictions)
                && !root.endorsed(address(this))
                && (
                    fullRestrictions.isFrozen(address(token), _getActor()) == true
                        || fullRestrictions.isFrozen(address(token), to) == true
                )
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

        // LP-2: Frozen must revert — only under FullRestrictions.
        // Endorsed addresses (including CryticTester) bypass frozen check in the hook.
        if (
            address(token.hook()) == address(fullRestrictions)
                && !root.endorsed(address(this))
                && (
                    fullRestrictions.isFrozen(address(token), _getActor()) == true
                        || fullRestrictions.isFrozen(address(token), to) == true
                )
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
        // Use vault.asset() (fixed) not _getAsset() (switchable) for consistent ghost keying
        sumOfClaimedDepositCancelations[vault.asset()] += assets;
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

    /// @dev Deposit on behalf of another user via operator approval (ERC-7540 operator path)
    function vault_deposit_as_operator(uint256 assets, uint256 ownerEntropy) public updateGhosts {
        address owner = _getRandomActor(ownerEntropy);
        if (owner == _getActor()) return; // same as normal deposit
        if (!vault.isOperator(owner, _getActor())) return; // must be approved operator

        vm.prank(_getActor());
        try vault.deposit(assets, owner) returns (uint256 shares) {
            sumOfClaimedDeposits[address(token)] += shares;
        } catch {}
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

        // Skip if receiver IS the poolEscrow or globalEscrow — self-transfer makes delta measurement meaningless
        if (to == poolEscrowAddr || to == address(escrow)) return;

        // PE_5: snapshot reserved before
        uint128 reservedBefore;
        {
            (address peAsset, uint256 peTokenId) = spoke.idToAsset(AssetId.wrap(assetId));
            (, reservedBefore) =
                PoolEscrow(payable(poolEscrowAddr)).holding(ShareClassId.wrap(scId), peAsset, peTokenId);
        }

        // Use vault.asset() (fixed) — _getAsset() changes with switch_asset, breaking delta measurement
        address vaultAsset = vault.asset();
        uint256 tokenReceiverB4 = MockERC20(vaultAsset).balanceOf(to);
        uint256 tokenEscrowB4 = MockERC20(vaultAsset).balanceOf(poolEscrowAddr);

        vm.prank(_getActor());
        uint256 assets = vault.redeem(shares, to, _getActor());

        // Use vault.asset() (fixed) not _getAsset() (switchable) for consistent ghost keying
        sumOfClaimedRedemptions[vaultAsset] += assets;

        // PE_5: track reserved delta (unreserve via ARM._withdraw)
        {
            (address peAsset, uint256 peTokenId) = spoke.idToAsset(AssetId.wrap(assetId));
            (, uint128 reservedAfter) =
                PoolEscrow(payable(poolEscrowAddr)).holding(ShareClassId.wrap(scId), peAsset, peTokenId);
            if (reservedBefore > reservedAfter) {
                ghostPoolEscrowReserved[keccak256(abi.encode(poolId, scId, peAsset, peTokenId))] -=
                    (reservedBefore - reservedAfter);
            }
        }

        uint256 tokenReceiverAfter = MockERC20(vaultAsset).balanceOf(to);
        uint256 tokenEscrowAfter = MockERC20(vaultAsset).balanceOf(poolEscrowAddr);

        unchecked {
            uint256 deltaReceiver = tokenReceiverAfter - tokenReceiverB4;
            eq(deltaReceiver, assets, "FoT-1");
            uint256 deltaEscrow = tokenEscrowB4 - tokenEscrowAfter;
            if (RECON_EXACT_BAL_CHECK) {
                eq(deltaReceiver, shares, "Extra LP-3");
            }
            eq(deltaReceiver, deltaEscrow, "7540-14");
        }
    }

    function vault_withdraw(uint256 assets, uint256 toEntropy) public updateGhosts {
        address to = _getRandomActor(toEntropy);
        address poolEscrowAddr = address(balanceSheet.escrow(PoolId.wrap(poolId)));

        // Skip if receiver IS the poolEscrow or globalEscrow — self-transfer makes delta measurement meaningless
        if (to == poolEscrowAddr || to == address(escrow)) return;

        // PE_5: snapshot reserved before
        uint128 reservedBefore;
        {
            (address peAsset, uint256 peTokenId) = spoke.idToAsset(AssetId.wrap(assetId));
            (, reservedBefore) =
                PoolEscrow(payable(poolEscrowAddr)).holding(ShareClassId.wrap(scId), peAsset, peTokenId);
        }

        // Use vault.asset() (fixed) — _getAsset() changes with switch_asset, breaking delta measurement
        address vaultAsset = vault.asset();
        uint256 tokenReceiverB4 = MockERC20(vaultAsset).balanceOf(to);
        uint256 tokenEscrowB4 = MockERC20(vaultAsset).balanceOf(poolEscrowAddr);

        vm.prank(_getActor());
        vault.withdraw(assets, to, _getActor());

        // Use vault.asset() (fixed) not _getAsset() (switchable) for consistent ghost keying
        sumOfClaimedRedemptions[vaultAsset] += assets;

        // PE_5: track reserved delta (unreserve via ARM._withdraw)
        {
            (address peAsset, uint256 peTokenId) = spoke.idToAsset(AssetId.wrap(assetId));
            (, uint128 reservedAfter) =
                PoolEscrow(payable(poolEscrowAddr)).holding(ShareClassId.wrap(scId), peAsset, peTokenId);
            if (reservedBefore > reservedAfter) {
                ghostPoolEscrowReserved[keccak256(abi.encode(poolId, scId, peAsset, peTokenId))] -=
                    (reservedBefore - reservedAfter);
            }
        }

        uint256 tokenReceiverAfter = MockERC20(vaultAsset).balanceOf(to);
        uint256 tokenEscrowAfter = MockERC20(vaultAsset).balanceOf(poolEscrowAddr);

        unchecked {
            uint256 deltaReceiver = tokenReceiverAfter - tokenReceiverB4;
            uint256 deltaEscrow = tokenEscrowB4 - tokenEscrowAfter;
            if (RECON_EXACT_BAL_CHECK) {
                eq(deltaReceiver, assets, "Extra LP-3");
            }
            eq(deltaReceiver, deltaEscrow, "7540-14");
        }
    }

    // === OPERATOR === //

    /// @dev Set operator approval on vault (ERC-7540)
    function vault_setOperator(address operator, bool approved) public asActor {
        if (operator == _getActor()) return; // CannotSetSelfAsOperator
        vault.setOperator(operator, approved);
    }

    // === VIEW TARGETS === //

    /// @dev BaseVaults + AsyncVault view coverage
    function vault_views() public view {
        address actor = _getActor();
        try vault.DOMAIN_SEPARATOR() {} catch {} // EIP-712
        try vault.supportsInterface(bytes4(0x2f0a18c5)) {} catch {} // IERC7575
        try vault.supportsInterface(bytes4(0x01ffc9a7)) {} catch {} // IERC165
        try vault.priceLastUpdated() {} catch {}
        try vault.isPermissioned(actor) {} catch {}
        try vault.pendingRedeemRequest(0, actor) {} catch {}
        try vault.claimableRedeemRequest(0, actor) {} catch {}
        try vault.pendingCancelRedeemRequest(0, actor) {} catch {}
        try vault.claimableCancelRedeemRequest(0, actor) {} catch {}
        try vault.pendingDepositRequest(0, actor) {} catch {}
        try vault.claimableDepositRequest(0, actor) {} catch {}
        try vault.pendingCancelDepositRequest(0, actor) {} catch {}
        try vault.claimableCancelDepositRequest(0, actor) {} catch {}
        try vault.previewDeposit(1e18) {} catch {}
        try vault.previewMint(1e18) {} catch {}
        try vault.previewWithdraw(1e18) {} catch {}
        try vault.previewRedeem(1e18) {} catch {}
        try vault.maxDeposit(actor) {} catch {}
        try vault.maxMint(actor) {} catch {}
    }

    /// @dev ShareToken view coverage
    function token_views() public view {
        try token.messageForTransferRestriction(0) {} catch {}
        try token.supportsInterface(bytes4(0x01ffc9a7)) {} catch {}
    }
}
