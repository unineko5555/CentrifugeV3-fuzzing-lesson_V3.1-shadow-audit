// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";
import {MockERC20} from "@recon/MockERC20.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";
import {IRequestManager} from "src/core/interfaces/IRequestManager.sol";

// Contracts
import {AsyncVault} from "src/vaults/AsyncVault.sol";
import {ShareToken} from "src/core/spoke/ShareToken.sol";

import {Properties} from "../properties/Properties.sol";

/// @title ManagerTargets
/// @notice Actor and pool switching targets for fuzzer diversity.
///         Allows the fuzzer to explore different actors and pool configurations.
abstract contract ManagerTargets is BaseTargetFunctions, Properties {
    // ===================================================================
    // Actor Switching
    // ===================================================================

    /// @dev Switch active actor (for operations that use _getActor())
    function switch_actor(uint256 entropy) public {
        _switchActor(entropy);
    }

    // ===================================================================
    // Pool Switching (when multiple pools exist)
    // ===================================================================

    /// @dev Switch active pool/shareClass/asset to a different one
    function switch_pool(uint64 poolEntropy, uint32 scEntropy) public poolExists {
        activePoolId = _getRandomPoolId(poolEntropy);
        activeScId = _getRandomShareClassId(activePoolId, scEntropy);
        activeAssetId = poolCurrency[activePoolId];

        // Update vault/token references if available
        address vaultAddr = address(vaultRegistry.vault(activePoolId, activeScId, activeAssetId, IRequestManager(address(asyncRequestManager))));
        if (vaultAddr != address(0)) {
            vault = AsyncVault(vaultAddr);
            token = ShareToken(address(spoke.shareToken(activePoolId, activeScId)));
        }
    }

    // ===================================================================
    // Asset Operations
    // ===================================================================

    /// @dev Mint test tokens to an actor
    function asset_mint(uint128 amount) public vaultExists {
        amount = _clampU128(amount, 1, uint128(1e30));
        address actor = _getActor();
        defaultAsset.mint(actor, uint256(amount));
    }

    /// @dev Approve test tokens from actor to vault
    function asset_approve(uint128 amount) public vaultExists {
        address actor = _getActor();
        vm.prank(actor);
        defaultAsset.approve(address(vault), uint256(amount));
    }

    /// @dev Approve escrow for actor
    function asset_approveEscrow(uint128 amount) public vaultExists {
        address actor = _getActor();
        vm.prank(actor);
        defaultAsset.approve(address(escrow), uint256(amount));
    }
}
