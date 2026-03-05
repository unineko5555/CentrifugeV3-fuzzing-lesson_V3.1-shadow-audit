// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Asserts} from "@chimera/Asserts.sol";
import {vm} from "@chimera/Hevm.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {BeforeAfter} from "../BeforeAfter.sol";

/// @title AccessControlProperties
/// @notice P-ACC-5 (unauthorized hub ops fail) + P-CS-11 (validUntil enforcement).
abstract contract AccessControlProperties is BeforeAfter, Asserts {
    // ===================================================================
    // P-ACC-5: Unauthorized Hub Operations Fail
    // ===================================================================

    /// @dev Non-manager calling Hub.updateSharePrice should revert
    function property_ACC_5_unauthorized_hub_ops_fail() public {
        if (createdPools.length == 0) return;

        address nonManager = address(0xDEAD);
        vm.prank(nonManager);
        try hub.updateSharePrice(activePoolId, activeScId, d18(1e18), uint64(block.timestamp)) {
            t(false, "P-ACC-5: non-manager updateSharePrice succeeded");
        } catch {}
    }

    // ===================================================================
    // P-CS-11: validUntil Enforcement
    // ===================================================================

    /// @dev After time warp past validUntil, actor should be invalid member
    function property_CS_11_validUntil_enforcement() public {
        if (address(token) == address(0)) return;
        if (address(fullRestrictions) == address(0)) return;

        address[] memory actors = _getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            try fullRestrictions.isMember(address(token), actors[i])
                returns (bool isValid, uint64 validUntil_)
            {
                if (validUntil_ < type(uint64).max && validUntil_ > 0) {
                    if (block.timestamp > validUntil_) {
                        t(!isValid, "P-CS-11: expired member still valid");
                    }
                }
            } catch {}
        }
    }
}
