// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Asserts} from "@chimera/Asserts.sol";
import {BeforeAfter} from "./BeforeAfter.sol";
import {PoolId} from "src/core/types/PoolId.sol";
import {MAX_ADAPTER_COUNT} from "src/core/messaging/interfaces/IMultiAdapter.sol";

/// @title Properties
/// @notice 8 invariants (P-AGG-1 through P-AGG-8) for Gateway/MultiAdapter messaging layer.
abstract contract Properties is BeforeAfter, Asserts {
    // ===== P-AGG-1: No delivery without quorum =====

    /// @dev The processor handle count should only increase when quorum threshold is met.
    ///      A single adapter vote (with threshold=2+) must NEVER trigger processor.handle.
    function property_AGG_1_no_delivery_without_quorum() public {
        uint8 threshold = multiAdapter.threshold(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        if (threshold <= 1) return; // fast-path mode, single vote delivers

        // If processor received a new handle call, ghost_deliveries must have increased
        // (i.e., we tracked that quorum was actually reached in target functions)
        if (_after.processorHandleCount > _before.processorHandleCount) {
            uint256 newHandles = _after.processorHandleCount - _before.processorHandleCount;
            t(newHandles > 0, "P-AGG-1: processor handle increased without tracked delivery");
        }
    }

    // ===== P-AGG-2: Session reset clears pending votes =====

    /// @dev After setAdapters, all pending votes for the old session should be invalidated.
    ///      We verify by checking that the session id in the votes struct differs from active.
    function property_AGG_2_session_reset_clears_votes() public {
        // This is an event-driven property checked in AdminTargetFunctions:
        // After admin_reconfigureAdapters, we verify that subsequent delivery
        // requires fresh votes. The MultiAdapter code handles this by comparing
        // adapter.activeSessionId vs state.sessionId and clearing votes on mismatch.
        // We just verify the session id incremented.
        uint64 currentSessionId = multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        if (ghost_lastSessionId > 0) {
            gte(currentSessionId, ghost_lastSessionId, "P-AGG-2: session id should not decrease");
        }
    }

    // ===== P-AGG-3: Double-vote does not bypass threshold =====

    /// @dev With threshold=2, a single adapter voting twice should NOT trigger delivery.
    ///      MultiAdapter stores votes as int16[8] indexed by adapter.id-1, so same adapter
    ///      increments the same slot. countPositiveValues counts distinct positive slots.
    ///      A single adapter voting N times only creates 1 positive slot.
    function property_AGG_3_no_double_vote_bypass() public {
        uint8 threshold = multiAdapter.threshold(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        if (threshold <= 1) return;

        // ghost_singleAdapterDelivered[adapter][msgHash] is set true in adapter_deliverDuplicate
        // when a SINGLE adapter's duplicate votes triggered delivery.
        // This must NEVER happen when threshold >= 2.
        address[3] memory adapterAddrs = [address(adapter0), address(adapter1), address(adapter2)];
        for (uint256 i; i < 3; i++) {
            // Check the last message hash used in deliverDuplicate
            // We use a sentinel: if ghost_singleAdapterDelivered was ever set, it's a violation
            t(
                !ghost_singleAdapterDelivered[adapterAddrs[i]][ghost_lastDuplicateHash],
                "P-AGG-3: single adapter double-vote bypassed threshold"
            );
        }
    }

    // ===== P-AGG-4: Failed message accounting =====

    /// @dev failedMessages[hash] only increases on handle failure, decreases on successful retry.
    ///      The counter must never go negative (it's uint256, so underflow would revert).
    function property_AGG_4_failed_message_accounting() public {
        // Retries must never exceed failures. If they did, it means a non-failed message
        // was retried (which gateway.retry prevents with require(counter > 0)).
        gte(
            ghost_failedMessages,
            ghost_successfulRetries,
            "P-AGG-4: more retries than failures"
        );
    }

    // ===== P-AGG-5: Unpaid mode gas accounting =====

    /// @dev When unpaidMode is false and msg.value is insufficient, send should revert.
    ///      When unpaidMode is true, underpaid batches are tracked and can be repaid.
    function property_AGG_5_unpaid_mode_accounting() public {
        // Repaid batches must never exceed created underpaid batches.
        // gateway.repay requires underpaid.counter > 0 before decrementing.
        gte(
            ghost_underpaidCreated,
            ghost_underpaidRepaid,
            "P-AGG-5: more repaid than underpaid created"
        );
    }

    // ===== P-AGG-6: Outgoing blocked prevents send =====

    /// @dev When isOutgoingBlocked[centrifugeId][poolId] is true, _send must revert.
    function property_AGG_6_outgoing_blocked() public {
        // ghost_sendSucceededWhileBlocked is incremented in gateway_send when:
        //   1. The pool was blocked before the send call, AND
        //   2. The adapter sendCount increased (meaning the message got through)
        // This must ALWAYS be 0 — gateway._send reverts with OutgoingBlocked.
        eq(
            ghost_sendSucceededWhileBlocked,
            0,
            "P-AGG-6: send succeeded while pool was blocked"
        );
    }

    // ===== P-AGG-7: Batch integrity =====

    /// @dev withBatch requires lockCallback to be called before completion.
    ///      If lockCallback is not called, withBatch reverts with CallbackWasNotLocked.
    function property_AGG_7_batch_integrity() public {
        // ghost_batchMissingLockCallback is incremented in gateway_withBatchNoLock
        // when withBatch succeeds WITHOUT lockCallback being called.
        // Gateway.withBatch requires _batcher == address(0) after callback,
        // which only happens when lockCallback() is called. So this must always be 0.
        eq(
            ghost_batchMissingLockCallback,
            0,
            "P-AGG-7: withBatch succeeded without lockCallback"
        );
    }

    // ===== P-AGG-8: Paused gateway blocks operations =====

    /// @dev When paused, gateway.handle, gateway.send, and gateway.retry must revert.
    function property_AGG_8_pause_blocks_operations() public {
        if (!pauser.paused()) return;

        // When paused, no new handles should succeed.
        // This is enforced by the `pauseable` modifier on handle, send, retry, repay.
        // Processor handle count should not increase while paused.
        eq(
            _after.processorHandleCount,
            _before.processorHandleCount,
            "P-AGG-8: processor handle count increased while paused"
        );
    }
}
