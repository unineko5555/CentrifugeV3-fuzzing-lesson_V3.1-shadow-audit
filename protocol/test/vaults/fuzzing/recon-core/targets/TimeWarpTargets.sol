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
}
