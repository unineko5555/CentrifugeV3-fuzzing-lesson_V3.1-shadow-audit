// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

import {Properties} from "../properties/Properties.sol";

/// @dev Root admin targets — pause, unpause, veto, endorse, file, timelock, relyContract, denyContract
abstract contract RootTargets is BaseTargetFunctions, Properties {
    /// @dev Emergency pause — sets root.paused = true
    function root_pause() public asAdmin {
        root.pause();
    }

    /// @dev Emergency unpause — sets root.paused = false
    function root_unpause() public asAdmin {
        root.unpause();
    }

    /// @dev Revoke endorsement for an address
    function root_veto(address user) public asAdmin {
        root.veto(user);
    }

    /// @dev Endorse an address (bypass FullRestrictions)
    function root_endorse(address user) public asAdmin {
        root.endorse(user);
    }

    /// @dev Update Root delay parameter
    function root_file_delay(uint256 newDelay) public asAdmin {
        try root.file("delay", newDelay) {} catch {}
    }

    /// @dev Execute a previously scheduled rely (delay=0 in setup, so immediately executable)
    function root_executeScheduledRely(address target) public {
        try root.executeScheduledRely(target) {} catch {}
    }

    /// @dev Ward a user on an external contract via Root
    function root_relyContract(address target, address user) public asAdmin {
        try root.relyContract(target, user) {} catch {}
    }

    /// @dev Remove ward for a user on an external contract via Root
    function root_denyContract(address target, address user) public asAdmin {
        try root.denyContract(target, user) {} catch {}
    }
}
