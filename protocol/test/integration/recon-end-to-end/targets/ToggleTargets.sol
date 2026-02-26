// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";

import {Properties} from "../properties/Properties.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title ToggleTargets
/// @notice Toggle flags and configuration switches for E2E fuzzer code path coverage.
abstract contract ToggleTargets is BaseTargetFunctions, Properties {
    // ===================================================================
    // Config Toggles
    // ===================================================================

    /// @dev Toggle exact balance checking mode
    function toggle_exactBalanceCheck() public updateGhostsWithType(OpType.TOGGLE) {
        RECON_EXACT_BAL_CHECK = !RECON_EXACT_BAL_CHECK;
    }

    /// @dev Toggle single deploy mode (allows/prevents second pool creation)
    function toggle_singleDeploy() public updateGhostsWithType(OpType.TOGGLE) {
        RECON_USE_SINGLE_DEPLOY = !RECON_USE_SINGLE_DEPLOY;
    }

    // ===================================================================
    // Time Manipulation
    // ===================================================================

    /// @dev Warp time forward (useful for testing time-dependent logic like validUntil)
    function toggle_warpTime(uint256 secondsForward) public updateGhostsWithType(OpType.TOGGLE) {
        secondsForward = secondsForward % 365 days; // max 1 year forward
        if (secondsForward < 1) secondsForward = 1;
        vm.warp(block.timestamp + secondsForward);
    }

    /// @dev Roll block number forward
    function toggle_rollBlock(uint256 blocksForward) public updateGhostsWithType(OpType.TOGGLE) {
        blocksForward = blocksForward % 10000; // max 10000 blocks
        if (blocksForward < 1) blocksForward = 1;
        vm.roll(block.number + blocksForward);
    }
}
