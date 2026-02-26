// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {AdapterTargetFunctions} from "./targets/AdapterTargetFunctions.sol";
import {GatewayTargetFunctions} from "./targets/GatewayTargetFunctions.sol";
import {AdminTargetFunctions} from "./targets/AdminTargetFunctions.sol";

/// @title TargetFunctions
/// @notice Aggregates all target function modules for the recon-aggregator suite.
abstract contract TargetFunctions is AdapterTargetFunctions, GatewayTargetFunctions, AdminTargetFunctions {}
