// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";

import {Properties} from "../properties/Properties.sol";

/// @dev FullRestrictions admin targets — freeze/unfreeze/updateMember
abstract contract FullRestrictionsTargets is BaseTargetFunctions, Properties {
    function fullRestrictions_updateMemberBasic(uint64 validUntil) public asAdmin {
        fullRestrictions.updateMember(address(token), _getActor(), validUntil);
    }

    function fullRestrictions_updateMember(address user, uint64 validUntil) public asAdmin {
        fullRestrictions.updateMember(address(token), user, validUntil);
    }

    function fullRestrictions_freeze(address) public asAdmin {
        fullRestrictions.freeze(address(token), _getActor());
    }

    function fullRestrictions_unfreeze(address) public asAdmin {
        fullRestrictions.unfreeze(address(token), _getActor());
    }
}
