// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {vm} from "@chimera/Hevm.sol";
import {MockERC20} from "@recon/MockERC20.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {AccountId} from "src/core/types/AccountId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {D18} from "src/misc/types/D18.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";

// Interfaces
import {IBaseVault} from "src/vaults/interfaces/IBaseVault.sol";
import {AsyncInvestmentState} from "src/vaults/interfaces/IVaultManagers.sol";
import {EpochId, UserOrder} from "src/vaults/interfaces/IBatchRequestManager.sol";

import {Setup} from "./Setup.sol";
import {ReconNAVManager} from "./managers/ReconNAVManager.sol";

/// @dev Operation types for before/after state tracking
enum OpType {
    GENERIC,
    ADMIN,
    // Hub operations
    BRM_REQUEST_DEPOSIT,
    BRM_REQUEST_REDEEM,
    BRM_CANCEL_DEPOSIT,
    BRM_CANCEL_REDEEM,
    BRM_APPROVE_DEPOSITS,
    BRM_ISSUE_SHARES,
    BRM_APPROVE_REDEEMS,
    BRM_REVOKE_SHARES,
    BRM_NOTIFY_DEPOSIT,
    BRM_NOTIFY_REDEEM,
    // Spoke operations
    VAULT_REQUEST_DEPOSIT,
    VAULT_REQUEST_REDEEM,
    VAULT_DEPOSIT,
    VAULT_MINT,
    VAULT_REDEEM,
    VAULT_WITHDRAW,
    VAULT_CANCEL_DEPOSIT,
    VAULT_CANCEL_REDEEM,
    // NAV
    NAV_UPDATE,
    NAV_CLOSE_GAIN_LOSS,
    // Queue
    BS_SUBMIT_QUEUED_ASSETS,
    BS_SUBMIT_QUEUED_SHARES,
    // Toggle
    TOGGLE,
    // Price Age
    PRICE_AGE_SET,
    // Liability
    LIABILITY_INIT,
    // Journal
    JOURNAL_UPDATE,
    // SyncManager
    SYNC_DEPOSIT,
    SYNC_MINT,
    // Hub notifications
    HUB_NOTIFY_PRICE,
    HUB_NOTIFY_METADATA
}

/// @title BeforeAfter
/// @notice Combined Hub+Spoke ghost state tracking for E2E property verification.
///         Captures state before and after each target function execution.
///         Split into sub-functions to avoid stack-too-deep.
abstract contract BeforeAfter is ReconNAVManager {
    struct Vars {
        // === Hub state === //
        uint128 hubDebited;
        uint128 hubCredited;
        mapping(PoolId => mapping(ShareClassId => mapping(AssetId => uint128))) hubPendingDeposit;
        mapping(PoolId => mapping(ShareClassId => mapping(AssetId => uint128))) hubPendingRedeem;
        mapping(PoolId => mapping(ShareClassId => mapping(AssetId => EpochId))) hubEpochId;
        mapping(PoolId => mapping(ShareClassId => mapping(AssetId => uint128))) hubHolding;
        mapping(PoolId => mapping(AccountId => uint128)) hubAccountValue;
        // Per-actor BRM state
        mapping(ShareClassId => mapping(AssetId => mapping(bytes32 => UserOrder))) hubDepositRequest;
        mapping(ShareClassId => mapping(AssetId => mapping(bytes32 => UserOrder))) hubRedeemRequest;

        // === Spoke state === //
        uint256 escrowTokenBalance;
        uint256 escrowShareBalance;
        uint256 totalShareSupply;
        // Per-actor investment state
        mapping(address => AsyncInvestmentState) investments;
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
        _captureState(_before);
    }

    function __after() internal {
        _captureState(_after);
    }

    function _captureState(Vars storage vars) internal {
        // --- Hub accounting (transient) ---
        vars.hubDebited = accounting.debited();
        vars.hubCredited = accounting.credited();

        // --- Per-pool state ---
        for (uint256 i = 0; i < createdPools.length; i++) {
            _capturePoolState(vars, createdPools[i]);
        }

        // --- Spoke state ---
        _captureSpokeState(vars);
    }

    /// @dev Capture hub state for a single pool (reduces stack depth)
    function _capturePoolState(Vars storage vars, PoolId pid) internal {
        AssetId aid = poolCurrency[pid];
        ShareClassId[] storage scs = poolShareClasses[pid];

        for (uint256 j = 0; j < scs.length; j++) {
            _captureShareClassState(vars, pid, scs[j], aid);
        }
    }

    /// @dev Capture hub state for a single (pool, shareClass, asset) tuple
    function _captureShareClassState(
        Vars storage vars,
        PoolId pid,
        ShareClassId scid,
        AssetId aid
    ) internal {
        // Hub: Holdings
        (, vars.hubHolding[pid][scid][aid],,) = holdings.holding(pid, scid, aid);

        // Hub: BRM epoch
        _captureEpochState(vars, pid, scid, aid);

        // Hub: BRM pending
        vars.hubPendingDeposit[pid][scid][aid] = brm.pendingDeposit(pid, scid, aid);
        vars.hubPendingRedeem[pid][scid][aid] = brm.pendingRedeem(pid, scid, aid);

        // Hub: per-actor BRM requests
        _captureActorBRMState(vars, pid, scid, aid);

        // Hub: account values
        _captureAccountValues(vars, pid, scid, aid);
    }

    /// @dev Capture epoch state (separate function to reduce stack depth)
    function _captureEpochState(
        Vars storage vars,
        PoolId pid,
        ShareClassId scid,
        AssetId aid
    ) internal {
        (uint32 dEp, uint32 iEp, uint32 rEp, uint32 rvEp) = brm.epochId(pid, scid, aid);
        vars.hubEpochId[pid][scid][aid] = EpochId({
            deposit: dEp,
            issue: iEp,
            redeem: rEp,
            revoke: rvEp
        });
    }

    /// @dev Capture per-actor BRM requests (separate function to reduce stack depth)
    function _captureActorBRMState(
        Vars storage vars,
        PoolId pid,
        ShareClassId scid,
        AssetId aid
    ) internal {
        address[] memory actors = _getActors();
        for (uint256 k = 0; k < actors.length; k++) {
            bytes32 actor = CastLib.toBytes32(actors[k]);
            _captureActorDeposit(vars, scid, aid, actor, pid);
            _captureActorRedeem(vars, scid, aid, actor, pid);
        }
    }

    function _captureActorDeposit(
        Vars storage vars,
        ShareClassId scid,
        AssetId aid,
        bytes32 actor,
        PoolId pid
    ) internal {
        (uint128 pending, uint32 lastUpdate) = brm.depositRequest(pid, scid, aid, actor);
        vars.hubDepositRequest[scid][aid][actor] = UserOrder({
            pending: pending,
            lastUpdate: lastUpdate
        });
    }

    function _captureActorRedeem(
        Vars storage vars,
        ShareClassId scid,
        AssetId aid,
        bytes32 actor,
        PoolId pid
    ) internal {
        (uint128 pending, uint32 lastUpdate) = brm.redeemRequest(pid, scid, aid, actor);
        vars.hubRedeemRequest[scid][aid][actor] = UserOrder({
            pending: pending,
            lastUpdate: lastUpdate
        });
    }

    /// @dev Capture account values (separate function to reduce stack depth)
    function _captureAccountValues(
        Vars storage vars,
        PoolId pid,
        ShareClassId scid,
        AssetId aid
    ) internal {
        for (uint8 kind = 0; kind < 6; kind++) {
            AccountId accountId = holdings.accountId(pid, scid, aid, kind);
            (,,, uint64 lastUpdated,) = accounting.accounts(pid, accountId);
            if (lastUpdated != 0) {
                (, uint128 accountValue) = accounting.accountValue(pid, accountId);
                vars.hubAccountValue[pid][accountId] = accountValue;
            }
        }
    }

    /// @dev Capture spoke-side state
    function _captureSpokeState(Vars storage vars) internal {
        if (address(vault) == address(0) || address(token) == address(0)) return;

        vars.escrowTokenBalance = MockERC20(vault.asset()).balanceOf(address(escrow));
        vars.escrowShareBalance = token.balanceOf(address(escrow));
        vars.totalShareSupply = token.totalSupply();

        // Per-actor investment state
        _captureActorInvestments(vars);
    }

    /// @dev Capture per-actor investment state (separate function)
    function _captureActorInvestments(Vars storage vars) internal {
        address[] memory actors = _getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            _captureOneActorInvestment(vars, actors[i]);
        }
    }

    /// @dev Capture one actor's investment state
    function _captureOneActorInvestment(Vars storage vars, address actor) internal {
        (
            uint128 maxMint,
            uint128 maxWithdraw,
            D18 depositPrice,
            D18 redeemPrice,
            uint128 pendingDepositRequest,
            uint128 pendingRedeemRequest,
            uint128 claimableCancelDepositRequest,
            uint128 claimableCancelRedeemRequest,
            bool pendingCancelDepositRequest,
            bool pendingCancelRedeemRequest
        ) = asyncRequestManager.investments(IBaseVault(address(vault)), actor);
        vars.investments[actor] = AsyncInvestmentState(
            maxMint,
            maxWithdraw,
            depositPrice,
            redeemPrice,
            pendingDepositRequest,
            pendingRedeemRequest,
            claimableCancelDepositRequest,
            claimableCancelRedeemRequest,
            pendingCancelDepositRequest,
            pendingCancelRedeemRequest
        );
    }
}
