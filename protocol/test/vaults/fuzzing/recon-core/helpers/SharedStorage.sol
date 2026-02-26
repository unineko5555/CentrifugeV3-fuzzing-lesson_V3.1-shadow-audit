// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

abstract contract SharedStorage {
    /**
     * GLOBAL SETTINGS
     */
    uint8 constant RECON_MODULO_DECIMALS = 19; // Caps to 18

    bool constant RECON_TOGGLE_CANARY_TESTS = false;
    bool RECON_SKIPPED_PROPERTY = true;
    bool TODO_RECON_SKIP_ERC7540 = false;
    bool TODO_RECON_SKIP_ACKNOWLEDGED_CASES = true;
    bool RECON_USE_SENTINEL_TESTS = false;
    bool RECON_USE_HARDCODED_DECIMALS = false;
    bool RECON_USE_SINGLE_DEPLOY = true;
    bool RECON_EXACT_BAL_CHECK = false;

    /// === INTERNAL COUNTERS === ///
    uint64 ASSET_ID_COUNTER = 1;
    uint16 DEFAULT_DESTINATION_CHAIN = 1;
    uint48 LOCAL_POOL_COUNTER = 0; // incremented before use in deployNewTokenPoolAndShare
    // Pool ID includes centrifugeId so isLocal check passes in _sendRequest
    uint64 POOL_ID = (uint64(DEFAULT_DESTINATION_CHAIN) << 48) | uint64(LOCAL_POOL_COUNTER);
    uint16 SHARE_COUNTER = 1;
    bytes16 SHARE_ID = bytes16(bytes32(uint256(SHARE_COUNTER)));
    uint128 ASSET_ID = uint128(bytes16(abi.encodePacked(DEFAULT_DESTINATION_CHAIN, uint32(1))));

    // NOTE: Step 1 — mapping from asset address to/from assetId
    mapping(address => uint128) assetAddressToAssetId;
    mapping(uint128 => address) assetIdToAssetAddress;

    address[] shareClassTokens;
    address[] vaults;

    // === Ghost: Deposit requests (indexed by asset) === //
    mapping(address => uint256) sumOfDepositRequests;
    mapping(address => uint256) sumOfClaimedRedemptions;
    mapping(address => uint256) sumOfTransfersIn;
    mapping(address => uint256) sumOfTransfersOut;

    // Global-1, Global-2
    mapping(address => uint256) cancelRedeemShareTokenPayout;
    mapping(address => uint256) cancelDepositCurrencyPayout;

    // Cancel request flags
    mapping(address => bool) hasRequestedDepositCancellation;
    mapping(address => bool) hasRequestedRedeemCancellation;

    // === Ghost: Share token tracking (indexed by share token) === //
    mapping(address => uint256) mintedByCurrencyPayout;
    mapping(address => uint256) sumOfFullfilledDeposits;
    mapping(address => uint256) sumOfClaimedDeposits;
    mapping(address => uint256) sumOfRedeemRequests;
    mapping(address => uint256) sumOfClaimedRequests;
    mapping(address => uint256) sumOfClaimedDepositCancelations;
    mapping(address => uint256) sumOfClaimedRedeemCancelations;

    // Legacy tracking
    mapping(address => uint256) totalCurrenciesSent;
    mapping(address => uint256) totalShareSent;

    // Global-3 tracking
    mapping(address => uint256) executedInvestments;
    mapping(address => uint256) executedRedemptions;
    mapping(address => uint256) incomingTransfers;
    mapping(address => uint256) outGoingTransfers;
    mapping(address => uint256) shareMints;

    // Global-1 and Global-2
    mapping(address => uint256) claimedAmounts;
    mapping(address => uint256) depositRequests;

    // Per-actor request tracking
    mapping(address => mapping(address => uint256)) requestDepositAssets;
    mapping(address => mapping(address => uint256)) requestRedeemShares;

    // === NEW v3.1 Ghost Maps === //
    // PoolEscrow tracking
    mapping(bytes32 => uint256) ghostPoolEscrowTotal; // keccak256(poolId) => total deposited
    mapping(bytes32 => uint256) ghostPoolEscrowReserved; // keccak256(poolId) => total reserved

    // VaultRegistry tracking
    mapping(address => bool) linkedVaults;
    uint256 linkedVaultCount;

    // RefundEscrow tracking
    mapping(bytes32 => uint256) refundEscrowDeposits; // keccak256(poolId) => deposits
    mapping(bytes32 => uint256) refundEscrowWithdrawals; // keccak256(poolId) => withdrawals
}
