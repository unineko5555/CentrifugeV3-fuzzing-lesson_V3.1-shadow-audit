// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";

import {Properties} from "../properties/Properties.sol";

/// @dev Time manipulation handlers to explore time-dependent behavior
///      (membership expiry, price staleness, scheduled relys)
abstract contract TimeWarpTargets is BaseTargetFunctions, Properties {
    /// @dev Large time jump (up to 365 days) — triggers membership expiry
    function time_warp(uint256 delta) public {
        delta = between(delta, 1, 365 days);
        vm.warp(block.timestamp + delta);
    }

    /// @dev Small time jump (up to 1 hour) — triggers price staleness
    function time_warp_small(uint256 delta) public {
        delta = between(delta, 1, 1 hours);
        vm.warp(block.timestamp + delta);
    }

    /// @dev Warp to exactly past member expiry — triggers P-TH-2/7 boundary
    ///      Targeted boundary test: random warp rarely lands on exact expiry edge
    function time_warp_to_member_expiry() public {
        if (address(token) == address(0)) return;
        if (address(fullRestrictions) == address(0)) return;
        address actor = _getActor();
        (bool isMember, uint64 validUntil) = fullRestrictions.isMember(address(token), actor);
        if (!isMember) return;
        if (validUntil == 0 || validUntil == type(uint64).max) return;
        if (block.timestamp >= validUntil) return; // already expired
        vm.warp(uint256(validUntil) + 1);
    }
}
