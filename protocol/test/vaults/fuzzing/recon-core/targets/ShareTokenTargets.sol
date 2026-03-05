// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";

import {ESCROW_HOOK_ID} from "src/core/spoke/interfaces/ITransferHook.sol";

import {Properties} from "../properties/Properties.sol";

/// @dev Share token transfer targets with restriction checks
abstract contract ShareTokenTargets is BaseTargetFunctions, Properties {
    function token_transfer(address to, uint256 value) public {
        require(_canDonate(to), "never donate to escrow");
        value = between(value, 0, token.balanceOf(_getActor()));

        bool hasReverted;
        vm.prank(_getActor());
        try token.transfer(to, value) {}
        catch {
            hasReverted = true;
        }

        // TT-1: Frozen must revert — only under FullRestrictions.
        // Endorsed addresses bypass frozen check per-address (BaseTransferHook.isSourceOrTargetFrozen).
        // FreelyTransferable hook ignores frozen status entirely.
        if (address(token.hook()) == address(fullRestrictions)) {
            bool fromBlocked = fullRestrictions.isFrozen(address(token), _getActor()) && !root.endorsed(_getActor());
            bool toBlocked = fullRestrictions.isFrozen(address(token), to) && !root.endorsed(to);
            if (fromBlocked || toBlocked) {
                t(hasReverted, "TT-1 Must Revert");
            }
        }

        // TT-3: Non-member must revert (skip 0-amount edge case)
        // Only applies under FullRestrictions — FreelyTransferable allows non-member transfers
        // Note: endorsed addresses bypass membership check via isTargetMember()
        // Note: ESCROW_HOOK_ID (0x1CF60) is a sentinel — FullRestrictions treats as redeem request
        if (value > 0 && to != ESCROW_HOOK_ID && address(token.hook()) == address(fullRestrictions)) {
            (bool isMember,) = fullRestrictions.isMember(address(token), to);
            if (!isMember && !root.endorsed(to)) {
                t(hasReverted, "TT-3 Must Revert");
            }
        }
    }

    function token_approve(address spender, uint256 value) public asActor {
        token.approve(spender, value);
    }

    function token_transferFrom(address to, uint256 value) public {
        address from = _getActor();
        require(_canDonate(to), "never donate to escrow");
        value = between(value, 0, token.balanceOf(from));

        bool hasReverted;
        vm.prank(from);
        try token.transferFrom(from, to, value) {}
        catch {
            hasReverted = true;
        }

        // TT-1: Frozen must revert — only under FullRestrictions.
        // Endorsed addresses bypass frozen check per-address (BaseTransferHook.isSourceOrTargetFrozen).
        // FreelyTransferable hook ignores frozen status entirely.
        if (address(token.hook()) == address(fullRestrictions)) {
            bool fromBlocked = fullRestrictions.isFrozen(address(token), from) && !root.endorsed(from);
            bool toBlocked = fullRestrictions.isFrozen(address(token), to) && !root.endorsed(to);
            if (fromBlocked || toBlocked) {
                t(hasReverted, "TT-1 Must Revert");
            }
        }

        // TT-3: Non-member check (skip 0-amount edge case)
        // Only applies under FullRestrictions — FreelyTransferable allows non-member transfers
        // Note: endorsed addresses bypass membership check via isTargetMember()
        // Note: ESCROW_HOOK_ID (0x1CF60) is a sentinel — FullRestrictions treats as redeem request
        if (value > 0 && to != ESCROW_HOOK_ID && address(token.hook()) == address(fullRestrictions)) {
            (bool isMember,) = fullRestrictions.isMember(address(token), to);
            if (!isMember && !root.endorsed(to)) {
                t(hasReverted, "TT-3 Must Revert");
            }
        }
    }
}
