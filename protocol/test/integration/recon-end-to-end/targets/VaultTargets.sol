// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";

// Types
import {D18} from "src/misc/types/D18.sol";

// Interfaces
import {IERC7540Deposit, IERC7540Redeem} from "src/misc/interfaces/IERC7540.sol";
import {IERC7887Deposit, IERC7887Redeem} from "src/misc/interfaces/IERC7540.sol";

import {Properties} from "../properties/Properties.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title VaultTargets
/// @notice Spoke-side vault operations for E2E fuzzing.
///         Uses ERC-7540/7887 vault interface. In E2E mode, vault.requestDeposit()
///         triggers a message to Hub (via real messaging), which processes the request
///         through the BatchRequestManager.
abstract contract VaultTargets is BaseTargetFunctions, Properties {
    // ===================================================================
    // Request Operations (send messages to hub via gateway)
    // ===================================================================

    /// @dev Request deposit via vault (spoke-side, sends message to hub)
    function vault_requestDeposit(uint128 assets) public updateGhostsWithType(OpType.VAULT_REQUEST_DEPOSIT) vaultExists {
        assets = _clampAmount(assets);
        address actor = _getActor();

        vm.prank(actor);
        try IERC7540Deposit(address(vault)).requestDeposit(uint256(assets), actor, actor) {
            sumOfDepositRequests[address(defaultAsset)] += assets;
            requestDepositAssets[address(vault)][actor] += assets;
        } catch {}
    }

    /// @dev Request redeem via vault (spoke-side, sends message to hub)
    function vault_requestRedeem(uint128 shares) public updateGhostsWithType(OpType.VAULT_REQUEST_REDEEM) vaultExists {
        shares = _clampAmount(shares);
        address actor = _getActor();

        vm.prank(actor);
        try IERC7540Redeem(address(vault)).requestRedeem(uint256(shares), actor, actor) {
            sumOfRedeemRequests[address(defaultAsset)] += shares;
            requestRedeemShares[address(vault)][actor] += shares;
        } catch {}
    }

    // ===================================================================
    // Cancel Operations
    // ===================================================================

    /// @dev Cancel deposit request via vault (ERC-7887)
    function vault_cancelDepositRequest() public updateGhostsWithType(OpType.VAULT_CANCEL_DEPOSIT) vaultExists {
        address actor = _getActor();

        vm.prank(actor);
        try IERC7887Deposit(address(vault)).cancelDepositRequest(0, actor) {
            hasRequestedDepositCancellation[actor] = true;
        } catch {}
    }

    /// @dev Cancel redeem request via vault (ERC-7887)
    function vault_cancelRedeemRequest() public updateGhostsWithType(OpType.VAULT_CANCEL_REDEEM) vaultExists {
        address actor = _getActor();

        vm.prank(actor);
        try IERC7887Redeem(address(vault)).cancelRedeemRequest(0, actor) {
            hasRequestedRedeemCancellation[actor] = true;
        } catch {}
    }

    /// @dev Claim cancel deposit (ERC-7887)
    function vault_claimCancelDepositRequest() public updateGhosts vaultExists {
        address actor = _getActor();

        vm.prank(actor);
        try IERC7887Deposit(address(vault)).claimCancelDepositRequest(0, actor, actor) returns (uint256 assets) {
            cancelDepositCurrencyPayout[actor] += assets;
            cancelExecuted = true;
        } catch {}
    }

    /// @dev Claim cancel redeem (ERC-7887)
    function vault_claimCancelRedeemRequest() public updateGhosts vaultExists {
        address actor = _getActor();

        vm.prank(actor);
        try IERC7887Redeem(address(vault)).claimCancelRedeemRequest(0, actor, actor) returns (uint256 shares) {
            cancelRedeemShareTokenPayout[actor] += shares;
        } catch {}
    }

    // ===================================================================
    // Claim Operations (ERC-4626 style)
    // ===================================================================

    /// @dev Execute deposit (claim shares for deposited assets)
    function vault_deposit(uint128 assets) public updateGhostsWithType(OpType.VAULT_DEPOSIT) vaultExists {
        assets = _clampAmount(assets);
        address actor = _getActor();

        vm.prank(actor);
        try vault.deposit(uint256(assets), actor) returns (uint256) {
            sumOfClaimedDeposits[address(defaultAsset)] += assets;
            depositExecuted = true;
        } catch {}
    }

    /// @dev Execute mint (claim specific number of shares)
    function vault_mint(uint128 shares) public updateGhostsWithType(OpType.VAULT_MINT) vaultExists {
        shares = _clampAmount(shares);
        address actor = _getActor();

        vm.prank(actor);
        try vault.mint(uint256(shares), actor) returns (uint256 assets) {
            sumOfClaimedDeposits[address(defaultAsset)] += assets;
            depositExecuted = true;
        } catch {}
    }

    /// @dev Execute redeem (claim assets for redeemed shares)
    function vault_redeem(uint128 shares) public updateGhostsWithType(OpType.VAULT_REDEEM) vaultExists {
        shares = _clampAmount(shares);
        address actor = _getActor();

        vm.prank(actor);
        try vault.redeem(uint256(shares), actor, actor) returns (uint256 assets) {
            sumOfClaimedRedemptions[address(defaultAsset)] += assets;
            redeemExecuted = true;
        } catch {}
    }

    /// @dev Execute withdraw (claim specific amount of assets)
    function vault_withdraw(uint128 assets) public updateGhostsWithType(OpType.VAULT_WITHDRAW) vaultExists {
        assets = _clampAmount(assets);
        address actor = _getActor();

        vm.prank(actor);
        try vault.withdraw(uint256(assets), actor, actor) returns (uint256) {
            sumOfClaimedRedemptions[address(defaultAsset)] += assets;
            redeemExecuted = true;
        } catch {}
    }
}
