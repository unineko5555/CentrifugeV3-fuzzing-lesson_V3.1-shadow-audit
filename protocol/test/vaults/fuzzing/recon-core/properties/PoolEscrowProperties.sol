// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Asserts} from "@chimera/Asserts.sol";
import {MockERC20} from "@recon/MockERC20.sol";

import {PoolEscrow} from "src/core/spoke/PoolEscrow.sol";
import {IPoolEscrow} from "src/core/spoke/interfaces/IPoolEscrow.sol";
import {PoolId} from "src/core/types/PoolId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AssetId} from "src/core/types/AssetId.sol";

import {Setup} from "../Setup.sol";

/// @dev PoolEscrow invariant properties — P-PE-1 through P-PE-5
abstract contract PoolEscrowProperties is Setup, Asserts {
    /// @dev P-PE-1: holding.total >= holding.reserved
    function property_PE_1() public {
        if (address(vault) == address(0)) return;
        if (poolId == 0) return;

        IPoolEscrow poolEscrowI = balanceSheet.escrow(PoolId.wrap(poolId));
        if (address(poolEscrowI) == address(0)) return;
        PoolEscrow poolEscrow_ = PoolEscrow(payable(address(poolEscrowI)));

        (address asset, uint256 tokenId) = spoke.idToAsset(AssetId.wrap(assetId));
        if (asset == address(0)) return;

        (uint128 total, uint128 reserved) = poolEscrow_.holding(ShareClassId.wrap(scId), asset, tokenId);
        gte(total, reserved, "P-PE-1: total < reserved in PoolEscrow");
    }

    /// @dev P-PE-2: ERC20 balance of PoolEscrow backs holding.total
    function property_PE_2() public {
        if (address(vault) == address(0)) return;
        if (poolId == 0) return;

        IPoolEscrow poolEscrowI = balanceSheet.escrow(PoolId.wrap(poolId));
        if (address(poolEscrowI) == address(0)) return;
        PoolEscrow poolEscrow_ = PoolEscrow(payable(address(poolEscrowI)));

        (address asset, uint256 tokenId) = spoke.idToAsset(AssetId.wrap(assetId));
        if (asset == address(0)) return;

        (uint128 total,) = poolEscrow_.holding(ShareClassId.wrap(scId), asset, tokenId);
        uint256 actualBalance = MockERC20(asset).balanceOf(address(poolEscrow_));
        gte(actualBalance, uint256(total), "P-PE-2: ERC20 balance < holding.total");
    }

    /// @dev P-PE-3: availableBalanceOf == total - reserved
    function property_PE_3() public {
        if (address(vault) == address(0)) return;
        if (poolId == 0) return;

        IPoolEscrow poolEscrowI = balanceSheet.escrow(PoolId.wrap(poolId));
        if (address(poolEscrowI) == address(0)) return;
        PoolEscrow poolEscrow_ = PoolEscrow(payable(address(poolEscrowI)));

        (address asset, uint256 tokenId) = spoke.idToAsset(AssetId.wrap(assetId));
        if (asset == address(0)) return;

        (uint128 total, uint128 reserved) = poolEscrow_.holding(ShareClassId.wrap(scId), asset, tokenId);
        uint128 available = poolEscrow_.availableBalanceOf(ShareClassId.wrap(scId), asset, tokenId);
        eq(uint256(available), uint256(total - reserved), "P-PE-3: available != total - reserved");
    }

    /// @dev P-PE-4: ghost total tracking — actual total >= ghost total
    function property_PE_4_ghost() public {
        if (address(vault) == address(0)) return;
        if (poolId == 0) return;

        IPoolEscrow poolEscrowI = balanceSheet.escrow(PoolId.wrap(poolId));
        if (address(poolEscrowI) == address(0)) return;
        PoolEscrow poolEscrow_ = PoolEscrow(payable(address(poolEscrowI)));

        (address asset, uint256 tokenId) = spoke.idToAsset(AssetId.wrap(assetId));
        if (asset == address(0)) return;

        bytes32 key = keccak256(abi.encode(poolId, scId, asset, tokenId));
        (uint128 total,) = poolEscrow_.holding(ShareClassId.wrap(scId), asset, tokenId);
        gte(uint256(total), ghostPoolEscrowTotal[key], "P-PE-4: total < ghost total");
    }

    /// @dev P-PE-5: ghost reserved tracking matches actual reserved
    function property_PE_5_reserved_ghost() public {
        if (address(vault) == address(0)) return;
        if (poolId == 0) return;

        IPoolEscrow poolEscrowI = balanceSheet.escrow(PoolId.wrap(poolId));
        if (address(poolEscrowI) == address(0)) return;
        PoolEscrow poolEscrow_ = PoolEscrow(payable(address(poolEscrowI)));

        (address asset, uint256 tokenId) = spoke.idToAsset(AssetId.wrap(assetId));
        if (asset == address(0)) return;

        bytes32 key = keccak256(abi.encode(poolId, scId, asset, tokenId));
        (, uint128 reserved) = poolEscrow_.holding(ShareClassId.wrap(scId), asset, tokenId);
        eq(uint256(reserved), ghostPoolEscrowReserved[key], "P-PE-5: reserved != ghost reserved");
    }
}
