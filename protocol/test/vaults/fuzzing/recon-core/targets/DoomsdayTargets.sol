// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";
import {MockERC20} from "@recon/MockERC20.sol";

import {IBaseVault} from "src/vaults/interfaces/IBaseVault.sol";
import {IAsyncVault} from "src/vaults/interfaces/IAsyncVault.sol";
import {PoolId} from "src/core/types/PoolId.sol";

import {Properties} from "../properties/Properties.sol";
import {OpType} from "../BeforeAfter.sol";

/// @dev Doomsday targets — extreme edge cases and view-never-reverts
abstract contract DoomsdayTargets is BaseTargetFunctions, Properties {
    /// @dev pricePerShare never changes after a user operation
    function doomsday_pricePerShare_never_changes_after_user_operation() public {
        if (currentOperation != OpType.ADMIN) {
            eq(_before.pricePerShare, _after.pricePerShare, "pricePerShare changed after user operation");
        }
    }

    /// @dev impliedPricePerShare never changes after user operation
    function doomsday_impliedPricePerShare_never_changes_after_user_operation() public {
        if (currentOperation != OpType.ADMIN) {
            if (_before.totalShareSupply == 0 || _after.totalShareSupply == 0) return;
            uint256 impliedBefore = _before.totalAssets / _before.totalShareSupply;
            uint256 impliedAfter = _after.totalAssets / _after.totalShareSupply;
            eq(impliedBefore, impliedAfter, "impliedPricePerShare changed after user operation");
        }
    }

    /// @dev View functions on vault should never revert
    function doomsday_vault_views_never_revert() public {
        if (address(vault) == address(0)) return;

        // maxDeposit, maxMint, maxRedeem, maxWithdraw
        try vault.maxDeposit(_getActor()) {} catch { t(false, "maxDeposit reverted"); }
        try vault.maxMint(_getActor()) {} catch { t(false, "maxMint reverted"); }
        try vault.maxRedeem(_getActor()) {} catch { t(false, "maxRedeem reverted"); }
        try vault.maxWithdraw(_getActor()) {} catch { t(false, "maxWithdraw reverted"); }

        // convertToShares, convertToAssets
        try vault.convertToShares(1e18) {} catch { t(false, "convertToShares reverted"); }
        try vault.convertToAssets(1e18) {} catch { t(false, "convertToAssets reverted"); }

        // totalAssets
        try vault.totalAssets() {} catch { t(false, "totalAssets reverted"); }
    }

    /// @dev View functions on spoke should never revert
    function doomsday_spoke_views_never_revert() public {
        if (address(spoke) == address(0)) return;

        try spoke.isPoolActive(PoolId.wrap(poolId)) {} catch { t(false, "isPoolActive reverted"); }
    }

    /// @dev View functions on asyncRequestManager should never revert
    function doomsday_arm_views_never_revert() public {
        if (address(asyncRequestManager) == address(0)) return;
        if (address(vault) == address(0)) return;

        try asyncRequestManager.investments(IBaseVault(address(vault)), _getActor()) {}
        catch { t(false, "investments reverted"); }

        try asyncRequestManager.convertToShares(IBaseVault(address(vault)), 1e18) {}
        catch { t(false, "ARM convertToShares reverted"); }

        try asyncRequestManager.convertToAssets(IBaseVault(address(vault)), 1e18) {}
        catch { t(false, "ARM convertToAssets reverted"); }
    }
}
