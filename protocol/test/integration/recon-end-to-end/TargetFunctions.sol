// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

import {Properties} from "./properties/Properties.sol";

// Wave 2 targets
import {AdminTargets} from "./targets/AdminTargets.sol";
import {HubTargets} from "./targets/HubTargets.sol";
import {ManagerTargets} from "./targets/ManagerTargets.sol";
import {ToggleTargets} from "./targets/ToggleTargets.sol";

// Wave 3 targets
import {BatchRequestTargets} from "./targets/BatchRequestTargets.sol";
import {VaultTargets} from "./targets/VaultTargets.sol";
import {BalanceSheetTargets} from "./targets/BalanceSheetTargets.sol";
import {NAVTargets} from "./targets/NAVTargets.sol";
import {PoolEscrowTargets} from "./targets/PoolEscrowTargets.sol";
import {ShareTokenTargets} from "./targets/ShareTokenTargets.sol";
import {DoomsdayTargets} from "./targets/DoomsdayTargets.sol";
import {QueueManagerTargets} from "./targets/QueueManagerTargets.sol";

// Wave 4 targets
import {PriceAgeTargets} from "./targets/PriceAgeTargets.sol";
import {LiabilityTargets} from "./targets/LiabilityTargets.sol";
import {JournalTargets} from "./targets/JournalTargets.sol";

// Wave 5 targets
import {SyncManagerTargets} from "./targets/SyncManagerTargets.sol";
import {HubNotificationTargets} from "./targets/HubNotificationTargets.sol";

/// @title TargetFunctions
/// @notice Composition of all target function modules for the E2E suite.
abstract contract TargetFunctions is
    BaseTargetFunctions,
    Properties,
    // Wave 2
    AdminTargets,
    HubTargets,
    ManagerTargets,
    ToggleTargets,
    // Wave 3
    BatchRequestTargets,
    VaultTargets,
    BalanceSheetTargets,
    NAVTargets,
    PoolEscrowTargets,
    ShareTokenTargets,
    DoomsdayTargets,
    QueueManagerTargets,
    // Wave 4 (Coverage expansion)
    PriceAgeTargets,
    LiabilityTargets,
    JournalTargets,
    // Wave 5 (Coverage expansion: SyncManager + Hub notifications)
    SyncManagerTargets,
    HubNotificationTargets
{
    // ===================================================================
    // Canary Invariants (verify fuzzer reaches interesting states)
    // ===================================================================

    function invariant_e2e_pool_created() public view returns (bool) {
        return poolCreated;
    }

    function invariant_e2e_vault_deployed() public view returns (bool) {
        return vaultDeployed;
    }

    function invariant_e2e_deposit_executed() public view returns (bool) {
        return depositExecuted;
    }

    function invariant_e2e_redeem_executed() public view returns (bool) {
        return redeemExecuted;
    }
}
