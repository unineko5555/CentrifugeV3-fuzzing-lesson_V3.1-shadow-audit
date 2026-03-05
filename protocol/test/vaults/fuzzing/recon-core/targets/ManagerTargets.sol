// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {vm} from "@chimera/Hevm.sol";
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {MockERC20} from "@recon/MockERC20.sol";

import {PoolId} from "src/core/types/PoolId.sol";

import {Properties} from "../properties/Properties.sol";

/// @dev Actor/asset switching and basic ERC20 handlers
abstract contract ManagerTargets is BaseTargetFunctions, Properties {
    function switch_actor(uint256 entropy) public {
        _switchActor(entropy);
    }

    function switch_asset(uint256 entropy) public {
        _switchAsset(entropy);
    }

    function add_new_asset(uint8 decimals) public returns (address) {
        return _newAsset(decimals);
    }

    function asset_approve(address to, uint128 amt) public updateGhosts asActor {
        MockERC20(_getAsset()).approve(to, amt);
    }

    function asset_mint(address to, uint128 amt) public updateGhosts asAdmin {
        require(to != address(escrow), "Cannot mint to escrow");
        MockERC20(_getAsset()).mint(to, amt);
    }

    /// @dev Direct token transfer to poolEscrow (donation attack vector)
    ///      Properties should still hold: donations only make escrow over-collateralized
    function donate_to_pool_escrow(uint128 amt) public {
        if (address(vault) == address(0)) return;
        if (poolId == 0) return;

        address poolEscrowAddr = address(balanceSheet.escrow(PoolId.wrap(poolId)));
        if (poolEscrowAddr == address(0)) return;

        address asset = vault.asset();
        uint256 balance = MockERC20(asset).balanceOf(_getActor());
        if (balance == 0) return;
        amt = uint128(uint256(amt) % balance);
        if (amt == 0) return;

        vm.prank(_getActor());
        MockERC20(asset).transfer(poolEscrowAddr, amt);
    }
}
