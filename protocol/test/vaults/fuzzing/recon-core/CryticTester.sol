// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {CryticAsserts} from "@chimera/CryticAsserts.sol";

import {TargetFunctions} from "./TargetFunctions.sol";

// FOUNDRY_PROFILE=echidna echidna . --contract CryticCoreTester --config echidna_core.yaml
// FOUNDRY_PROFILE=echidna medusa fuzz --config medusa_core.json
contract CryticCoreTester is TargetFunctions, CryticAsserts {
    constructor() payable {
        setup();
    }
}
