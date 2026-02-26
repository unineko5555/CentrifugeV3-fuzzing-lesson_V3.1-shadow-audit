// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Setup} from "../Setup.sol";
import {IBaseVault} from "src/vaults/interfaces/IBaseVault.sol";
import {D18} from "src/misc/types/D18.sol";

/// @title Ghost variable tracking for recon-core fuzzing
/// @notice Tracks min/max deposit and redeem prices per actor
abstract contract Ghosts is Setup {
    mapping(address => Vars) internal _investorsGlobals;

    struct Vars {
        uint256 maxDepositPrice;
        uint256 minDepositPrice;
        uint256 maxRedeemPrice;
        uint256 minRedeemPrice;
    }

    function __globals() internal {
        (uint256 depositPrice, uint256 redeemPrice) = _getDepositAndRedeemPrice();

        // Conditionally update max (always works on zero)
        _investorsGlobals[_getActor()].maxDepositPrice = depositPrice > _investorsGlobals[_getActor()].maxDepositPrice
            ? depositPrice
            : _investorsGlobals[_getActor()].maxDepositPrice;
        _investorsGlobals[_getActor()].maxRedeemPrice = redeemPrice > _investorsGlobals[_getActor()].maxRedeemPrice
            ? redeemPrice
            : _investorsGlobals[_getActor()].maxRedeemPrice;

        // Conditionally update min (on zero we must initialize)
        if (_investorsGlobals[_getActor()].minDepositPrice == 0) {
            _investorsGlobals[_getActor()].minDepositPrice = depositPrice;
        }
        if (_investorsGlobals[_getActor()].minRedeemPrice == 0) {
            _investorsGlobals[_getActor()].minRedeemPrice = redeemPrice;
        }

        // Conditional update after initialization
        _investorsGlobals[_getActor()].minDepositPrice = depositPrice < _investorsGlobals[_getActor()].minDepositPrice
            ? depositPrice
            : _investorsGlobals[_getActor()].minDepositPrice;
        _investorsGlobals[_getActor()].minRedeemPrice = redeemPrice < _investorsGlobals[_getActor()].minRedeemPrice
            ? redeemPrice
            : _investorsGlobals[_getActor()].minRedeemPrice;
    }

    function _getDepositAndRedeemPrice() internal view returns (uint256, uint256) {
        (,, D18 depositPrice, D18 redeemPrice,,,,,,) =
            asyncRequestManager.investments(IBaseVault(address(vault)), address(_getActor()));

        return (uint256(depositPrice.raw()), uint256(redeemPrice.raw()));
    }
}
