// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {AccountId} from "src/core/types/AccountId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {EpochId, UserOrder} from "src/vaults/interfaces/IBatchRequestManager.sol";

/// @title SharedStorage
/// @notice Ghost variables and configuration flags for the recon-e2e E2E fuzzing suite.
///         Combines hub-side and spoke-side ghost state tracking for cross-system property verification.
abstract contract SharedStorage {
    // ===================================================================
    // Config
    // ===================================================================

    uint16 constant HUB_CENTRIFUGE_ID = 1;
    uint16 constant SPOKE_CENTRIFUGE_ID = 2;

    bool RECON_USE_SINGLE_DEPLOY = true;
    bool RECON_EXACT_BAL_CHECK = false;

    // ===================================================================
    // Pool Management State
    // ===================================================================

    PoolId[] createdPools;
    mapping(PoolId => ShareClassId[]) poolShareClasses;
    mapping(PoolId => AssetId) poolCurrency;

    // ===================================================================
    // Asset Tracking
    // ===================================================================

    mapping(address => uint128) assetAddressToAssetId;
    mapping(uint128 => address) assetIdToAssetAddress;

    address[] shareClassTokens;
    address[] vaultAddresses;

    // ===================================================================
    // Hub-Side Ghost Variables
    // ===================================================================

    // BRM pending tracking
    mapping(PoolId => mapping(ShareClassId => mapping(AssetId => uint128))) ghostPendingDeposit;
    mapping(PoolId => mapping(ShareClassId => mapping(AssetId => uint128))) ghostPendingRedeem;
    mapping(PoolId => mapping(ShareClassId => mapping(AssetId => EpochId))) ghostEpochIds;

    // Per-actor BRM tracking
    mapping(ShareClassId => mapping(AssetId => mapping(bytes32 => UserOrder))) ghostDepositRequest;
    mapping(ShareClassId => mapping(AssetId => mapping(bytes32 => UserOrder))) ghostRedeemRequest;

    // Holdings ghost
    mapping(PoolId => mapping(ShareClassId => mapping(AssetId => uint128))) ghostHoldingAmount;

    // Account value ghosts
    mapping(PoolId => mapping(AccountId => uint128)) ghostAccountValue;

    // ===================================================================
    // Spoke-Side Ghost Variables
    // ===================================================================

    // Escrow tracking
    mapping(address => uint256) ghostEscrowTokenBalance;
    mapping(address => uint256) ghostEscrowShareBalance;

    // PoolEscrow tracking
    mapping(bytes32 => uint256) ghostPoolEscrowTotal;
    mapping(bytes32 => uint256) ghostPoolEscrowReserved;

    // VaultRegistry tracking
    mapping(address => bool) ghostVaultLinked;
    uint256 ghostLinkedVaultCount;

    // ===================================================================
    // Cross-System Ghost Variables
    // ===================================================================

    // Share issuance: Hub totalIssuance vs Spoke ShareToken.totalSupply
    mapping(bytes32 => uint128) ghostHubSharesIssued;   // keccak256(poolId, scId) => total
    mapping(bytes32 => uint256) ghostSpokeShareSupply;   // keccak256(poolId, scId) => total

    // Message counter
    uint256 ghostCrossChainMessageCount;

    // ===================================================================
    // Request Tracking (per-asset cumulative sums for spoke-side)
    // ===================================================================

    mapping(address => uint256) sumOfDepositRequests;
    mapping(address => uint256) sumOfRedeemRequests;
    mapping(address => uint256) sumOfClaimedDeposits;
    mapping(address => uint256) sumOfClaimedRedemptions;

    // Per-actor request tracking
    mapping(address => mapping(address => uint256)) requestDepositAssets;
    mapping(address => mapping(address => uint256)) requestRedeemShares;

    // Cancel request flags
    mapping(address => bool) hasRequestedDepositCancellation;
    mapping(address => bool) hasRequestedRedeemCancellation;

    // Cancel payout tracking
    mapping(address => uint256) cancelDepositCurrencyPayout;
    mapping(address => uint256) cancelRedeemShareTokenPayout;

    // ===================================================================
    // Counters
    // ===================================================================

    uint64 POOL_ID_COUNTER = 1;
    uint64 ASSET_ID_COUNTER = 1;

    // ===================================================================
    // Canaries (for verifying fuzzer reaches interesting states)
    // ===================================================================

    bool poolCreated;
    bool vaultDeployed;
    bool depositExecuted;
    bool redeemExecuted;
    bool cancelExecuted;
    bool priceUpdated;
}
