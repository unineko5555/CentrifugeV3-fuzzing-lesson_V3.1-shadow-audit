// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {TargetFunctions} from "./TargetFunctions.sol";
import {CryticAsserts} from "@chimera/CryticAsserts.sol";

/// @title CryticAggregatorTester
/// @notice Entry point for Echidna and Medusa aggregator fuzzing.
///         MathLib linking: Echidna uses deployContracts config (echidna_aggregator.yaml),
///         Medusa/crytic-compile handles linking automatically.
contract CryticAggregatorTester is TargetFunctions, CryticAsserts {
    constructor() payable {
        setup();
    }
}
