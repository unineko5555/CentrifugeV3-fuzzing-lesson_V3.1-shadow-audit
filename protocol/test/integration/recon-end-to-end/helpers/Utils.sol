// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId, newAssetId} from "src/core/types/AssetId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";

/// @title Utils
/// @notice Utility helpers for the recon-e2e E2E fuzzing suite.
///         Provides address conversion, value clamping, and type helpers.
abstract contract Utils {
    using CastLib for *;

    // ===================================================================
    // Value Clamping
    // ===================================================================

    /// @dev Clamp uint128 to [min, max]
    function _clampU128(uint128 value, uint128 min, uint128 max) internal pure returns (uint128) {
        if (max <= min) return min;
        return min + (value % (max - min + 1));
    }

    /// @dev Clamp uint256 to [min, max]
    function _clampU256(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
        if (max <= min) return min;
        return min + (value % (max - min + 1));
    }

    /// @dev Clamp uint64 to [min, max]
    function _clampU64(uint64 value, uint64 min, uint64 max) internal pure returns (uint64) {
        if (max <= min) return min;
        return min + (value % (max - min + 1));
    }

    // ===================================================================
    // Address Conversion
    // ===================================================================

    /// @dev Convert address to bytes32 (for BRM user identification)
    function _toBytes32(address addr) internal pure returns (bytes32) {
        return CastLib.toBytes32(addr);
    }

    /// @dev Convert bytes32 to address
    function _toAddress(bytes32 b) internal pure returns (address) {
        return address(uint160(uint256(b)));
    }

    // ===================================================================
    // Pool/Asset/ShareClass ID Helpers
    // ===================================================================

    /// @dev Create a PoolId from centrifugeId and local counter
    function _makePoolId(uint16 centrifugeId, uint48 localCounter) internal pure returns (PoolId) {
        uint64 raw = (uint64(centrifugeId) << 48) | uint64(localCounter);
        return PoolId.wrap(raw);
    }

    /// @dev Create an AssetId from centrifugeId and local counter
    function _makeAssetId(uint16 centrifugeId, uint32 localCounter) internal pure returns (AssetId) {
        return newAssetId(centrifugeId, localCounter);
    }

    /// @dev Hash (poolId, scId) for cross-system tracking keys
    function _poolScKey(PoolId poolId, ShareClassId scId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(PoolId.unwrap(poolId), ShareClassId.unwrap(scId)));
    }

    /// @dev Hash poolId for pool-level keys
    function _poolKey(PoolId poolId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(PoolId.unwrap(poolId)));
    }

    // ===================================================================
    // Price Helpers
    // ===================================================================

    /// @dev Clamp a raw price to a reasonable range [0.01e18, 100e18]
    function _clampPrice(uint256 rawPrice) internal pure returns (uint256) {
        return _clampU256(rawPrice, 0.01e18, 100e18);
    }

    /// @dev Clamp an amount to a reasonable range [1, 1e24]
    function _clampAmount(uint128 rawAmount) internal pure returns (uint128) {
        return _clampU128(rawAmount, 1, uint128(1e24));
    }
}
