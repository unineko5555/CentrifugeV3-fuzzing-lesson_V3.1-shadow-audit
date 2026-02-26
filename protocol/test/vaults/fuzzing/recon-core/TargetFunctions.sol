// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

import {Properties} from "./properties/Properties.sol";
import {ShareTokenTargets} from "./targets/ShareTokenTargets.sol";
import {GatewayMockTargets} from "./targets/GatewayMockTargets.sol";
import {FullRestrictionsTargets} from "./targets/FullRestrictionsTargets.sol";
import {VaultTargets} from "./targets/VaultTargets.sol";
import {VaultCallbackTargets} from "./targets/VaultCallbackTargets.sol";
import {ManagerTargets} from "./targets/ManagerTargets.sol";
import {DoomsdayTargets} from "./targets/DoomsdayTargets.sol";
import {PoolEscrowTargets} from "./targets/PoolEscrowTargets.sol";
import {BalanceSheetTargets} from "./targets/BalanceSheetTargets.sol";
import {VaultRegistryTargets} from "./targets/VaultRegistryTargets.sol";
import {SyncManagerTargets} from "./targets/SyncManagerTargets.sol";

abstract contract TargetFunctions is
    BaseTargetFunctions,
    Properties,
    ShareTokenTargets,
    GatewayMockTargets,
    FullRestrictionsTargets,
    VaultTargets,
    VaultCallbackTargets,
    ManagerTargets,
    DoomsdayTargets,
    PoolEscrowTargets,
    BalanceSheetTargets,
    VaultRegistryTargets,
    SyncManagerTargets
{
    function invariant_doesTokenGetDeployed() public view returns (bool) {
        if (RECON_TOGGLE_CANARY_TESTS) {
            return _getAssets().length < 10;
        }
        return true;
    }

    function invariant_doesSharesGetDeployed() public view returns (bool) {
        if (RECON_TOGGLE_CANARY_TESTS) {
            return shareClassTokens.length < 10;
        }
        return true;
    }

    function invariant_doesVaultsGetDeployed() public view returns (bool) {
        if (RECON_TOGGLE_CANARY_TESTS) {
            return vaults.length < 10;
        }
        return true;
    }
}
