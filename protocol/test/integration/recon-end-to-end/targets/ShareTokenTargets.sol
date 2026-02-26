// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";

import {Properties} from "../properties/Properties.sol";

/// @title ShareTokenTargets
/// @notice ERC-20 share token operations for E2E fuzzing.
///         Tests token transfer, approval, and transferFrom functionality
///         under FullRestrictions hook constraints.
abstract contract ShareTokenTargets is BaseTargetFunctions, Properties {
    // ===================================================================
    // ERC-20 Operations
    // ===================================================================

    /// @dev Transfer share tokens between actors
    function token_transfer(uint256 actorEntropy, uint128 amount) public vaultExists {
        address from = _getActor();
        address to = _getRandomActor(actorEntropy);
        if (from == to) return;

        amount = _clampU128(amount, 1, uint128(token.balanceOf(from)));
        if (amount == 0) return;

        vm.prank(from);
        try token.transfer(to, uint256(amount)) {} catch {}
    }

    /// @dev Approve share tokens for another actor
    function token_approve(uint256 actorEntropy, uint128 amount) public vaultExists {
        address owner = _getActor();
        address spender = _getRandomActor(actorEntropy);

        vm.prank(owner);
        try token.approve(spender, uint256(amount)) {} catch {}
    }

    /// @dev TransferFrom share tokens (requires prior approval)
    function token_transferFrom(uint256 fromEntropy, uint256 toEntropy, uint128 amount) public vaultExists {
        address caller = _getActor();
        address from = _getRandomActor(fromEntropy);
        address to = _getRandomActor(toEntropy);
        if (from == to) return;

        uint256 balance = token.balanceOf(from);
        uint256 allowance = token.allowance(from, caller);
        uint256 maxTransfer = balance < allowance ? balance : allowance;

        amount = _clampU128(amount, 1, uint128(maxTransfer));
        if (amount == 0) return;

        vm.prank(caller);
        try token.transferFrom(from, to, uint256(amount)) {} catch {}
    }
}
