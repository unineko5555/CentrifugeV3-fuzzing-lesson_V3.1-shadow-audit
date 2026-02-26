// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";

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

        // TT-1: Always revert if frozen
        if (
            fullRestrictions.isFrozen(address(token), to) == true
                || fullRestrictions.isFrozen(address(token), _getActor()) == true
        ) {
            t(hasReverted, "TT-1 Must Revert");
        }

        // TT-3: Non-member must revert (skip 0-amount edge case)
        if (value > 0) {
            (bool isMember,) = fullRestrictions.isMember(address(token), to);
            if (!isMember) {
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

        // TT-1: Frozen check
        if (
            fullRestrictions.isFrozen(address(token), to) == true
                || fullRestrictions.isFrozen(address(token), from) == true
        ) {
            t(hasReverted, "TT-1 Must Revert");
        }

        // TT-3: Non-member check (skip 0-amount edge case)
        if (value > 0) {
            (bool isMember,) = fullRestrictions.isMember(address(token), to);
            if (!isMember) {
                t(hasReverted, "TT-3 Must Revert");
            }
        }
    }
}
