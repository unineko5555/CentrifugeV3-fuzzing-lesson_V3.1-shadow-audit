// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

import {Properties} from "../Properties.sol";

/// @title ToggleTargets
/// @notice Toggle targets for controlling fuzzer state variables.
///         Defined as separate functions to avoid stack-too-deep errors.
abstract contract ToggleTargets is BaseTargetFunctions, Properties {
    function toggle_IsLiability() public {
        IS_LIABILITY = !IS_LIABILITY;
    }

    function toggle_IsIncrease() public {
        IS_INCREASE = !IS_INCREASE;
    }

    function toggle_AccountToUpdate(uint8 accountToUpdate) public {
        ACCOUNT_TO_UPDATE = createdAccountIds[accountToUpdate % createdAccountIds.length];
    }

    function toggle_AssetAccount(uint32 assetAccountAsUint) public {
        ASSET_ACCOUNT = assetAccountAsUint;
    }

    function toggle_EquityAccount(uint32 equityAccountAsUint) public {
        EQUITY_ACCOUNT = equityAccountAsUint;
    }

    function toggle_LossAccount(uint32 lossAccountAsUint) public {
        LOSS_ACCOUNT = lossAccountAsUint;
    }

    function toggle_GainAccount(uint32 gainAccountAsUint) public {
        GAIN_ACCOUNT = gainAccountAsUint;
    }

    function toggle_IsDebitNormal() public {
        IS_DEBIT_NORMAL = !IS_DEBIT_NORMAL;
    }

    function toggle_MaxClaims(uint32 maxClaims) public {
        MAX_CLAIMS = maxClaims;
    }

    function toggle_NowEpochId(uint32 nowEpochId) public {
        NOW_EPOCH_ID = nowEpochId;
    }

    function toggle_IsSnapshot() public {
        IS_SNAPSHOT = !IS_SNAPSHOT;
    }

    function toggle_Nonce() public {
        NONCE++;
    }
}
