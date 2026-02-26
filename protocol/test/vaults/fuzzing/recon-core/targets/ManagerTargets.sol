// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {vm} from "@chimera/Hevm.sol";
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {MockERC20} from "@recon/MockERC20.sol";

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
}
