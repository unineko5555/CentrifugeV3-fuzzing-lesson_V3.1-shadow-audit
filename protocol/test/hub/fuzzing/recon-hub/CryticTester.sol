// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {CryticAsserts} from "@chimera/CryticAsserts.sol";

import {TargetFunctions} from "./TargetFunctions.sol";

// FOUNDRY_PROFILE=echidna echidna . --contract CryticTester --config echidna_hub.yaml
// medusa fuzz --config medusa/hub.json
contract CryticTester is TargetFunctions, CryticAsserts {
    constructor() payable {
        setup();
    }
}
