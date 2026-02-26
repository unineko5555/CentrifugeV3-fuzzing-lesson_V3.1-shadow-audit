// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

// Types
import {ShareClassId} from "src/core/types/ShareClassId.sol";

// Contracts
import {IPoolEscrow} from "src/core/spoke/interfaces/IPoolEscrow.sol";

import {Properties} from "../properties/Properties.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title PoolEscrowTargets
/// @notice PoolEscrow target functions for E2E fuzzing (new in v3.1).
///         PoolEscrow holds assets for a specific pool and manages reserved amounts.
///         Function signatures: (ShareClassId, address asset, uint256 tokenId, uint128 value)
abstract contract PoolEscrowTargets is BaseTargetFunctions, Properties {
    // ===================================================================
    // PoolEscrow Operations
    // ===================================================================

    /// @dev Deposit assets into the pool escrow
    function poolEscrow_deposit(uint128 amount) public updateGhosts vaultExists {
        amount = _clampAmount(amount);
        address escrowAddr = _getPoolEscrow();
        if (escrowAddr == address(0)) return;

        try IPoolEscrow(escrowAddr).deposit(activeScId, address(defaultAsset), 0, amount) {
            bytes32 key = _poolEscrowKey(escrowAddr);
            ghostPoolEscrowTotal[key] += amount;
        } catch {}
    }

    /// @dev Withdraw assets from the pool escrow
    function poolEscrow_withdraw(uint128 amount) public updateGhosts vaultExists {
        amount = _clampAmount(amount);
        address escrowAddr = _getPoolEscrow();
        if (escrowAddr == address(0)) return;

        try IPoolEscrow(escrowAddr).withdraw(activeScId, address(defaultAsset), 0, amount) {
            bytes32 key = _poolEscrowKey(escrowAddr);
            if (ghostPoolEscrowTotal[key] >= amount) {
                ghostPoolEscrowTotal[key] -= amount;
            }
        } catch {}
    }

    /// @dev Reserve assets in the pool escrow
    function poolEscrow_reserve(uint128 amount) public updateGhosts vaultExists {
        amount = _clampAmount(amount);
        address escrowAddr = _getPoolEscrow();
        if (escrowAddr == address(0)) return;

        try IPoolEscrow(escrowAddr).reserve(activeScId, address(defaultAsset), 0, amount) {
            bytes32 key = _poolEscrowKey(escrowAddr);
            ghostPoolEscrowReserved[key] += amount;
        } catch {}
    }

    /// @dev Unreserve assets in the pool escrow
    function poolEscrow_unreserve(uint128 amount) public updateGhosts vaultExists {
        amount = _clampAmount(amount);
        address escrowAddr = _getPoolEscrow();
        if (escrowAddr == address(0)) return;

        try IPoolEscrow(escrowAddr).unreserve(activeScId, address(defaultAsset), 0, amount) {
            bytes32 key = _poolEscrowKey(escrowAddr);
            if (ghostPoolEscrowReserved[key] >= amount) {
                ghostPoolEscrowReserved[key] -= amount;
            }
        } catch {}
    }

    // ===================================================================
    // Helpers
    // ===================================================================

    /// @dev Get the PoolEscrow address for the active pool (if it exists)
    function _getPoolEscrow() internal view returns (address) {
        try balanceSheet.escrow(activePoolId) returns (IPoolEscrow pe) {
            return address(pe);
        } catch {
            return address(0);
        }
    }

    /// @dev Create a key for PoolEscrow ghost tracking
    function _poolEscrowKey(address escrowAddr) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(escrowAddr));
    }
}
