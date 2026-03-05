// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Asserts} from "@chimera/Asserts.sol";

import {BeforeAfter} from "../BeforeAfter.sol";
import {CrossSystemProperties} from "./CrossSystemProperties.sol";
import {BatchRequestE2EProperties} from "./BatchRequestE2EProperties.sol";
import {HubAccountingProperties} from "./HubAccountingProperties.sol";
import {NAVProperties} from "./NAVProperties.sol";
import {EscrowProperties} from "./EscrowProperties.sol";
import {VaultE2EProperties} from "./VaultE2EProperties.sol";
import {AccessControlProperties} from "./AccessControlProperties.sol";
import {CrossPoolProperties} from "./CrossPoolProperties.sol";
import {SyncManagerProperties} from "./SyncManagerProperties.sol";

/// @title Properties
/// @notice Composition of all E2E property modules.
///         Inherits: CrossSystem (P-CS-1~9), BatchRequest (P-BRM-E2E-1~4),
///         HubAccounting (P-ACC-1~5), NAV (P-NAV-1~3), Escrow (P-E-1~2, P-PE-1~3),
///         VaultE2E (P-V-1~8), AccessControl (P-ACC-5, P-CS-11), CrossPool (P-CS-10),
///         SyncManager (P-SM-1~3).
abstract contract Properties is
    BeforeAfter,
    Asserts,
    CrossSystemProperties,
    BatchRequestE2EProperties,
    HubAccountingProperties,
    NAVProperties,
    EscrowProperties,
    VaultE2EProperties,
    AccessControlProperties,
    CrossPoolProperties,
    SyncManagerProperties
{}
