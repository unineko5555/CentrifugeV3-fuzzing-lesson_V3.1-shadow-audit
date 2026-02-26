// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";

import {PoolId} from "src/core/types/PoolId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {IVault} from "src/core/spoke/interfaces/IVault.sol";
import {IVaultFactory} from "src/core/spoke/factories/interfaces/IVaultFactory.sol";

import {Properties} from "../properties/Properties.sol";

/// @dev VaultRegistry targets — NEW in v3.1
abstract contract VaultRegistryTargets is BaseTargetFunctions, Properties {
    /// @dev Check vault is linked
    function vaultRegistry_isLinked() public view {
        if (vaults.length == 0) return;
        // P-VR-1: only linked vaults can serve requests
        assert(vaultRegistry.isLinked(IVault(vaults[0])));
    }

    /// @dev Unlink and relink the vault
    function vaultRegistry_unlinkAndRelink() public asAdmin {
        if (vaults.length == 0) return;
        IVault v = IVault(vaults[0]);

        if (!vaultRegistry.isLinked(v)) return;

        vaultRegistry.unlinkVault(PoolId.wrap(poolId), ShareClassId.wrap(scId), AssetId.wrap(assetId), v);

        // P-VR-3: no double link — relinking after unlink should work
        vaultRegistry.linkVault(PoolId.wrap(poolId), ShareClassId.wrap(scId), AssetId.wrap(assetId), v);
    }
}
