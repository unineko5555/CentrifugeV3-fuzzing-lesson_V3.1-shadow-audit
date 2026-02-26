// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Setup} from "./Setup.sol";
import {PoolId} from "src/core/types/PoolId.sol";
import {MAX_ADAPTER_COUNT} from "src/core/messaging/interfaces/IMultiAdapter.sol";

/// @title BeforeAfter
/// @notice Captures gateway/multiAdapter state before and after each target call
///         for inductive property checking.
abstract contract BeforeAfter is Setup {
    struct Snapshot {
        uint256 processorHandleCount;
        bool isPaused;
        uint256 gatewayBalance;
    }

    Snapshot internal _before;
    Snapshot internal _after;

    /// @dev Ghost: cumulative count of quorum-reached deliveries
    uint256 internal ghost_deliveries;

    /// @dev Ghost: track adapter → message → vote count within current session
    ///      Keyed by (adapterAddr, messageHash) to detect double-voting
    mapping(address => mapping(bytes32 => uint256)) internal ghost_adapterVotes;

    /// @dev Ghost: track session id at last setAdapters call
    uint64 internal ghost_lastSessionId;

    /// @dev Ghost: tracks per-adapter, per-message whether delivery occurred when only that adapter voted
    ///      Used by P-AGG-3 to detect if a single adapter's duplicate votes bypassed threshold
    mapping(address => mapping(bytes32 => bool)) internal ghost_singleAdapterDelivered;

    /// @dev Ghost: last message hash used in adapter_deliverDuplicate (for P-AGG-3 property check)
    bytes32 internal ghost_lastDuplicateHash;

    /// @dev Ghost: cumulative failed message count (incremented when processor fails)
    uint256 internal ghost_failedMessages;

    /// @dev Ghost: cumulative successful retries
    uint256 internal ghost_successfulRetries;

    /// @dev Ghost: cumulative underpaid batches created
    uint256 internal ghost_underpaidCreated;

    /// @dev Ghost: cumulative underpaid batches repaid
    uint256 internal ghost_underpaidRepaid;

    /// @dev Ghost: counts sends that succeeded while pool was blocked (should always be 0)
    uint256 internal ghost_sendSucceededWhileBlocked;

    /// @dev Ghost: cumulative successful withBatch calls
    uint256 internal ghost_batchSuccesses;

    /// @dev Ghost: cumulative withBatch calls that reverted due to missing lockCallback
    uint256 internal ghost_batchMissingLockCallback;

    function _before_() internal {
        _before.processorHandleCount = processor.handleCount();
        _before.isPaused = pauser.paused();
        _before.gatewayBalance = address(gateway).balance;
    }

    function _after_() internal {
        _after.processorHandleCount = processor.handleCount();
        _after.isPaused = pauser.paused();
        _after.gatewayBalance = address(gateway).balance;
    }
}
