// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {TargetFunctions} from "./TargetFunctions.sol";
import {CryticAsserts} from "@chimera/CryticAsserts.sol";

/// @title CryticTester
/// @notice Entry point for Echidna and Medusa E2E fuzzing.
contract CryticTester is TargetFunctions, CryticAsserts {
    constructor() payable {
        setup();
    }
}
