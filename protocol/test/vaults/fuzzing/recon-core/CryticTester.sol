// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {CryticAsserts} from "@chimera/CryticAsserts.sol";

import {TargetFunctions} from "./TargetFunctions.sol";

// FOUNDRY_PROFILE=echidna echidna . --contract CryticTester --config echidna_core.yaml --format text --workers 16 --test-limit 100000000
// medusa fuzz --config medusa_core.json
contract CryticTester is TargetFunctions, CryticAsserts {
    constructor() payable {
        setup();
    }
}
