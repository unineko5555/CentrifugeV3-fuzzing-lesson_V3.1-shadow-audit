// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {TargetFunctions} from "./TargetFunctions.sol";
import {CryticAsserts} from "@chimera/CryticAsserts.sol";

/// @title CryticTester
/// @notice Entry point for Echidna and Medusa aggregator fuzzing.
///         MathLib linking: Echidna uses deployContracts config (echidna_aggregator.yaml),
///         Medusa/crytic-compile handles linking automatically.
contract CryticTester is TargetFunctions, CryticAsserts {
    constructor() payable {
        setup();
    }
}

/// @title AggregatorCryticTester
/// @notice Unique name for Medusa targetContracts disambiguation.
///         Explicit payable constructor required — implicit constructors are non-payable,
///         which conflicts with Medusa's targetContractsBalances.
contract AggregatorCryticTester is CryticTester {
    constructor() payable {}
}
