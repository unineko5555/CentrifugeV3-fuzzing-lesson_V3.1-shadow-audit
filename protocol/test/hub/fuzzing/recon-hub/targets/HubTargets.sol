// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera deps
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {console2} from "forge-std/console2.sol";

// Recon Helpers
import {Panic} from "@recon/Panic.sol";

// Dependencies
import {CastLib} from "src/misc/libraries/CastLib.sol";

// Types
import {PoolId, newPoolId} from "src/core/types/PoolId.sol";
import {AssetId, newAssetId} from "src/core/types/AssetId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";

// Utils
import {Helpers} from "../utils/Helpers.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";

abstract contract HubTargets is BaseTargetFunctions, Properties {
    // ========================================================================
    // Pool Creation
    // ========================================================================

    function hub_createPool(address admin, uint64 poolIdAsUint, uint128 assetIdAsUint)
        public
        updateGhosts
        asActor
        returns (PoolId poolId)
    {
        PoolId _poolId = PoolId.wrap(poolIdAsUint);
        AssetId _assetId = AssetId.wrap(assetIdAsUint);

        hub.createPool(_poolId, admin, _assetId);

        poolCreated = true;
        createdPools.push(_poolId);

        return _poolId;
    }

    function hub_createPool_clamped(uint64 poolIdAsUint, uint128 assetEntropy)
        public
        updateGhosts
        asActor
        returns (PoolId)
    {
        AssetId _assetId = _getRandomAssetId(assetEntropy);
        return hub_createPool(_getActor(), poolIdAsUint, _assetId.raw());
    }

    // ========================================================================
    // Notify Deposit / Redeem (BRM claims via gateway callback)
    // ========================================================================

    function hub_notifyDeposit(uint64 poolIdAsUint, bytes16 scIdAsBytes, uint128 assetIdAsUint, uint32 maxClaims)
        public
        updateGhosts
        asActor
    {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = AssetId.wrap(assetIdAsUint);
        bytes32 investor = CastLib.toBytes32(_getActor());

        brm.notifyDeposit(poolId, scId, assetId, investor, maxClaims, address(0));
    }

    function hub_notifyDeposit_clamped(uint64 poolIdEntropy, uint32 scIdEntropy, uint32 maxClaims)
        public
        updateGhosts
        asActor
    {
        PoolId poolId = _getRandomPoolId(poolIdEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scIdEntropy);
        AssetId assetId = hubRegistry.currency(poolId);

        hub_notifyDeposit(poolId.raw(), scId.raw(), assetId.raw(), maxClaims);
    }

    function hub_notifyRedeem(uint64 poolIdAsUint, bytes16 scIdAsBytes, uint128 assetIdAsUint, uint32 maxClaims)
        public
        updateGhosts
        asActor
    {
        PoolId poolId = PoolId.wrap(poolIdAsUint);
        ShareClassId scId = ShareClassId.wrap(scIdAsBytes);
        AssetId assetId = AssetId.wrap(assetIdAsUint);
        bytes32 investor = CastLib.toBytes32(_getActor());

        brm.notifyRedeem(poolId, scId, assetId, investor, maxClaims, address(0));
    }

    function hub_notifyRedeem_clamped(uint64 poolEntropy, uint32 scIdEntropy, uint32 maxClaims)
        public
        updateGhosts
        asActor
    {
        PoolId poolId = _getRandomPoolId(poolEntropy);
        ShareClassId scId = _getRandomShareClassIdForPool(poolId, scIdEntropy);
        AssetId assetId = hubRegistry.currency(poolId);

        hub_notifyRedeem(poolId.raw(), scId.raw(), assetId.raw(), maxClaims);
    }

    // ========================================================================
    // Multicall (batch execution)
    // ========================================================================

    function hub_multicall(bytes[] memory data) public payable updateGhostsWithType(OpType.BATCH) asActor {
        hub.multicall{value: msg.value}(data);
    }

    function hub_multicall_clamped() public payable {
        this.hub_multicall{value: msg.value}(queuedCalls);
        queuedCalls = new bytes[](0);
    }
}
