// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";

import {PoolId} from "src/core/types/PoolId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {IPoolEscrow} from "src/core/spoke/interfaces/IPoolEscrow.sol";
import {PoolEscrow} from "src/core/spoke/PoolEscrow.sol";

import {Properties} from "../properties/Properties.sol";

/// @dev PoolEscrow targets — NEW in v3.1
abstract contract PoolEscrowTargets is BaseTargetFunctions, Properties {
    function _getPoolEscrow() internal view returns (IPoolEscrow) {
        return asyncRequestManager.poolEscrow(PoolId.wrap(poolId));
    }

    function _poolEscrowKey(address asset, uint256 tokenId) internal view returns (bytes32) {
        return keccak256(abi.encode(poolId, scId, asset, tokenId));
    }

    function poolEscrow_deposit(uint128 amount) public updateGhosts asAdmin {
        (address asset, uint256 tokenId) = spoke.idToAsset(AssetId.wrap(assetId));
        balanceSheet.deposit(PoolId.wrap(poolId), ShareClassId.wrap(scId), asset, tokenId, amount);
        ghostPoolEscrowTotal[_poolEscrowKey(asset, tokenId)] += amount;
    }

    function poolEscrow_withdraw(uint128 amount, address receiver) public updateGhosts asAdmin {
        (address asset, uint256 tokenId) = spoke.idToAsset(AssetId.wrap(assetId));
        balanceSheet.withdraw(PoolId.wrap(poolId), ShareClassId.wrap(scId), asset, tokenId, receiver, amount);
        ghostPoolEscrowTotal[_poolEscrowKey(asset, tokenId)] -= amount;
    }

    function poolEscrow_reserve(uint128 amount) public updateGhosts asAdmin {
        (address asset, uint256 tokenId) = spoke.idToAsset(AssetId.wrap(assetId));

        // Clamp to available balance: reserve cannot exceed total - reserved
        IPoolEscrow poolEscrowI = balanceSheet.escrow(PoolId.wrap(poolId));
        if (address(poolEscrowI) == address(0)) return;
        PoolEscrow poolEscrow_ = PoolEscrow(payable(address(poolEscrowI)));
        uint128 available = poolEscrow_.availableBalanceOf(ShareClassId.wrap(scId), asset, tokenId);
        if (amount > available) amount = available;
        if (amount == 0) return;

        balanceSheet.reserve(PoolId.wrap(poolId), ShareClassId.wrap(scId), asset, tokenId, amount);
        ghostPoolEscrowReserved[_poolEscrowKey(asset, tokenId)] += amount;
    }

    function poolEscrow_unreserve(uint128 amount) public updateGhosts asAdmin {
        (address asset, uint256 tokenId) = spoke.idToAsset(AssetId.wrap(assetId));

        // Clamp to current reserved
        IPoolEscrow poolEscrowI = balanceSheet.escrow(PoolId.wrap(poolId));
        if (address(poolEscrowI) == address(0)) return;
        PoolEscrow poolEscrow_ = PoolEscrow(payable(address(poolEscrowI)));
        (, uint128 reserved) = poolEscrow_.holding(ShareClassId.wrap(scId), asset, tokenId);
        if (amount > reserved) amount = reserved;
        if (amount == 0) return;

        balanceSheet.unreserve(PoolId.wrap(poolId), ShareClassId.wrap(scId), asset, tokenId, amount);
        ghostPoolEscrowReserved[_poolEscrowKey(asset, tokenId)] -= amount;
    }

    /// @dev Unclamped reserve — allows amount > available to test bound checking
    ///      Defense-in-depth for Finding 1 (PoolEscrow.reserve missing bound check)
    function poolEscrow_reserve_unclamped(uint128 amount) public updateGhosts asAdmin {
        (address asset, uint256 tokenId) = spoke.idToAsset(AssetId.wrap(assetId));
        IPoolEscrow poolEscrowI = balanceSheet.escrow(PoolId.wrap(poolId));
        if (address(poolEscrowI) == address(0)) return;
        if (amount == 0) return;
        // NO clamping — let the protocol handle (or fail to handle) the bound check
        try balanceSheet.reserve(PoolId.wrap(poolId), ShareClassId.wrap(scId), asset, tokenId, amount) {
            ghostPoolEscrowReserved[_poolEscrowKey(asset, tokenId)] += amount;
        } catch {
            // Expected to revert if amount > available — this is correct behavior
        }
    }
}
