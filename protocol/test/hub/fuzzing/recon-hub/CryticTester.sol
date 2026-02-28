// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {CryticAsserts} from "@chimera/CryticAsserts.sol";

import {TargetFunctions} from "./TargetFunctions.sol";

// FOUNDRY_PROFILE=echidna echidna . --contract CryticHubTester --config echidna_hub.yaml
// FOUNDRY_PROFILE=echidna medusa fuzz --config medusa_hub.json
contract CryticHubTester is TargetFunctions, CryticAsserts {
    constructor() payable {
        setup();
    }
}
