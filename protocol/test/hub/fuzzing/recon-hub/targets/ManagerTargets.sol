// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera deps
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

// Recon Helpers
import {MockERC20} from "@recon/MockERC20.sol";

// Utils
import {BeforeAfter} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";

/// @title ManagerTargets
/// @notice Actor and asset switching targets for fuzzer diversity.
abstract contract ManagerTargets is BaseTargetFunctions, Properties {
    /// @dev Switch to a different actor
    function switch_actor(uint256 entropy) public {
        _switchActor(entropy);
    }

    /// @dev Switch to a different asset
    function switch_asset(uint256 entropy) public {
        _switchAsset(entropy);
    }

    /// @dev Deploy a new token and add it to the asset list
    function add_new_asset(uint8 decimals) public returns (address) {
        address newAsset = _newAsset(decimals);
        return newAsset;
    }

    /// @dev Approve to arbitrary address
    function asset_approve(address to, uint128 amt) public updateGhosts asActor {
        MockERC20(_getAsset()).approve(to, amt);
    }

    /// @dev Mint to arbitrary address
    function asset_mint(address to, uint128 amt) public updateGhosts asAdmin {
        MockERC20(_getAsset()).mint(to, amt);
    }
}
