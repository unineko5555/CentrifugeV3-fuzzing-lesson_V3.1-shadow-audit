// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {AccountId} from "src/core/types/AccountId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";

// Interfaces
import {IAccounting} from "src/core/hub/interfaces/IAccounting.sol";
import {AccountType} from "src/core/hub/interfaces/IHub.sol";
import {EpochId, UserOrder} from "src/vaults/interfaces/IBatchRequestManager.sol";

// Setup
import {Setup} from "./Setup.sol";

enum OpType {
    GENERIC,
    DEPOSIT,
    REDEEM,
    BATCH,
    APPROVE_DEPOSITS,
    ISSUE_SHARES,
    APPROVE_REDEEMS,
    REVOKE_SHARES,
    CLOSE_EPOCH,
    UPDATE_NAV,
    CLOSE_GAIN_LOSS,
    SET_ORACLE_PRICE
}

/// @title BeforeAfter
/// @notice Ghost variable tracking for before/after state comparison in property checks.
abstract contract BeforeAfter is Setup {
    struct Vars {
        // Accounting ghosts (note: transient storage cleared after lock, so we snapshot during unlock)
        uint128 ghostDebited;
        uint128 ghostCredited;
        // Holdings ghosts
        mapping(PoolId => mapping(ShareClassId => mapping(AssetId => uint128))) ghostHolding;
        // Account value ghosts
        mapping(PoolId => mapping(AccountId => uint128)) ghostAccountValue;
        // BatchRequestManager epoch ghosts
        mapping(PoolId => mapping(ShareClassId => mapping(AssetId => EpochId))) ghostEpochId;
        // BatchRequestManager pending ghosts
        mapping(PoolId => mapping(ShareClassId => mapping(AssetId => uint128))) ghostPendingDeposit;
        mapping(PoolId => mapping(ShareClassId => mapping(AssetId => uint128))) ghostPendingRedeem;
        // BatchRequestManager user order ghosts
        mapping(ShareClassId => mapping(AssetId => mapping(bytes32 => UserOrder))) ghostDepositRequest;
        mapping(ShareClassId => mapping(AssetId => mapping(bytes32 => UserOrder))) ghostRedeemRequest;
    }

    Vars internal _before;
    Vars internal _after;
    OpType internal currentOperation;

    modifier updateGhosts() {
        currentOperation = OpType.GENERIC;
        __before();
        _;
        __after();
    }

    modifier updateGhostsWithType(OpType op) {
        currentOperation = op;
        __before();
        _;
        __after();
    }

    function __before() internal {
        _before.ghostDebited = accounting.debited();
        _before.ghostCredited = accounting.credited();

        for (uint256 i = 0; i < createdPools.length; i++) {
            address[] memory _actors = _getActors();
            PoolId poolId = createdPools[i];

            for (uint32 j = 0; j < shareClassManager.shareClassCount(poolId); j++) {
                ShareClassId scId = shareClassManager.previewShareClassId(poolId, j);
                AssetId assetId = hubRegistry.currency(poolId);

                // Holdings ghost
                (, _before.ghostHolding[poolId][scId][assetId],,) = holdings.holding(poolId, scId, assetId);

                // BatchRequestManager epoch ghost
                (uint32 depositEpoch, uint32 issueEpoch, uint32 redeemEpoch, uint32 revokeEpoch) =
                    brm.epochId(poolId, scId, assetId);
                _before.ghostEpochId[poolId][scId][assetId] =
                    EpochId({deposit: depositEpoch, issue: issueEpoch, redeem: redeemEpoch, revoke: revokeEpoch});

                // BatchRequestManager pending ghosts
                _before.ghostPendingDeposit[poolId][scId][assetId] = brm.pendingDeposit(poolId, scId, assetId);
                _before.ghostPendingRedeem[poolId][scId][assetId] = brm.pendingRedeem(poolId, scId, assetId);

                // Per-actor ghosts
                for (uint256 k = 0; k < _actors.length; k++) {
                    bytes32 actor = CastLib.toBytes32(_actors[k]);

                    // BRM deposit request ghost
                    (uint128 depositPending, uint32 depositLastUpdate) =
                        brm.depositRequest(poolId, scId, assetId, actor);
                    _before.ghostDepositRequest[scId][assetId][actor] =
                        UserOrder({pending: depositPending, lastUpdate: depositLastUpdate});

                    // BRM redeem request ghost
                    (uint128 redeemPending, uint32 redeemLastUpdate) =
                        brm.redeemRequest(poolId, scId, assetId, actor);
                    _before.ghostRedeemRequest[scId][assetId][actor] =
                        UserOrder({pending: redeemPending, lastUpdate: redeemLastUpdate});
                }

                // Account value ghosts
                for (uint8 kind = 0; kind < 6; kind++) {
                    AccountId accountId = holdings.accountId(poolId, scId, assetId, kind);
                    (,,, uint64 lastUpdated,) = accounting.accounts(poolId, accountId);
                    if (lastUpdated != 0) {
                        (, uint128 accountValue) = accounting.accountValue(poolId, accountId);
                        _before.ghostAccountValue[poolId][accountId] = accountValue;
                    }
                }
            }
        }
    }

    function __after() internal {
        _after.ghostDebited = accounting.debited();
        _after.ghostCredited = accounting.credited();

        for (uint256 i = 0; i < createdPools.length; i++) {
            address[] memory _actors = _getActors();
            PoolId poolId = createdPools[i];

            for (uint32 j = 0; j < shareClassManager.shareClassCount(poolId); j++) {
                ShareClassId scId = shareClassManager.previewShareClassId(poolId, j);
                AssetId assetId = hubRegistry.currency(poolId);

                // Holdings ghost
                (, _after.ghostHolding[poolId][scId][assetId],,) = holdings.holding(poolId, scId, assetId);

                // BatchRequestManager epoch ghost
                (uint32 depositEpoch, uint32 issueEpoch, uint32 redeemEpoch, uint32 revokeEpoch) =
                    brm.epochId(poolId, scId, assetId);
                _after.ghostEpochId[poolId][scId][assetId] =
                    EpochId({deposit: depositEpoch, issue: issueEpoch, redeem: redeemEpoch, revoke: revokeEpoch});

                // BatchRequestManager pending ghosts
                _after.ghostPendingDeposit[poolId][scId][assetId] = brm.pendingDeposit(poolId, scId, assetId);
                _after.ghostPendingRedeem[poolId][scId][assetId] = brm.pendingRedeem(poolId, scId, assetId);

                // Per-actor ghosts
                for (uint256 k = 0; k < _actors.length; k++) {
                    bytes32 actor = CastLib.toBytes32(_actors[k]);

                    (uint128 depositPending, uint32 depositLastUpdate) =
                        brm.depositRequest(poolId, scId, assetId, actor);
                    _after.ghostDepositRequest[scId][assetId][actor] =
                        UserOrder({pending: depositPending, lastUpdate: depositLastUpdate});

                    (uint128 redeemPending, uint32 redeemLastUpdate) =
                        brm.redeemRequest(poolId, scId, assetId, actor);
                    _after.ghostRedeemRequest[scId][assetId][actor] =
                        UserOrder({pending: redeemPending, lastUpdate: redeemLastUpdate});
                }

                // Account value ghosts
                for (uint8 kind = 0; kind < 6; kind++) {
                    AccountId accountId = holdings.accountId(poolId, scId, assetId, kind);
                    (,,, uint64 lastUpdated,) = accounting.accounts(poolId, accountId);
                    if (lastUpdated != 0) {
                        (, uint128 accountValue) = accounting.accountValue(poolId, accountId);
                        _after.ghostAccountValue[poolId][accountId] = accountValue;
                    }
                }
            }
        }
    }
}
