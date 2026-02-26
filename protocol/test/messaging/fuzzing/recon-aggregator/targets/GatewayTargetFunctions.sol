// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {vm} from "@chimera/Hevm.sol";
import {Properties} from "../Properties.sol";
import {PoolId} from "src/core/types/PoolId.sol";

/// @title GatewayTargetFunctions
/// @notice Target functions for Gateway outgoing, retry, batch, repay, and unpaid mode.
abstract contract GatewayTargetFunctions is Properties {
    /// @dev Direct gateway.handle (must come from auth'd caller = multiAdapter)
    ///      This tests that unauthorized callers are rejected.
    function gateway_handleDirect(uint64 poolIdRaw) public {
        _before_();

        bytes memory message = _buildNotifyPoolMessage(poolIdRaw);
        try gateway.handle(REMOTE_CENTRIFUGE_ID, message) {} catch {}

        _after_();
    }

    /// @dev Send an outgoing message via gateway (this contract is auth'd = deployer ward)
    function gateway_send(uint64 poolIdRaw) public {
        _before_();

        bytes memory message = _buildNotifyPoolMessage(poolIdRaw);
        bytes32 batchHash = keccak256(message);
        PoolId poolId = PoolId.wrap(poolIdRaw);

        bool wasBlocked = gateway.isOutgoingBlocked(REMOTE_CENTRIFUGE_ID, poolId);
        (, uint64 counterBefore) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);
        uint256 sendCountBefore = adapter0.sendCount() + adapter1.sendCount() + adapter2.sendCount();

        // We need to set unpaid mode since our adapters have 0 estimate cost
        // and we're not sending ETH. Gateway will use unpaidMode path.
        try gateway.send{value: 0}(REMOTE_CENTRIFUGE_ID, message, 0, address(this)) {} catch {}

        uint256 sendCountAfter = adapter0.sendCount() + adapter1.sendCount() + adapter2.sendCount();
        (, uint64 counterAfter) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);

        if (counterAfter > counterBefore) {
            ghost_underpaidCreated++;
        }

        // If pool was blocked and adapters still sent, that's a violation
        if (wasBlocked && sendCountAfter > sendCountBefore) {
            ghost_sendSucceededWhileBlocked++;
        }

        _after_();
    }

    /// @dev Toggle unpaid mode
    function gateway_setUnpaidMode(bool enabled) public {
        _before_();

        try gateway.setUnpaidMode(enabled) {} catch {}

        _after_();
    }

    /// @dev Retry a failed message
    function gateway_retry(uint64 poolIdRaw) public {
        _before_();

        bytes memory message = _buildNotifyPoolMessage(poolIdRaw);
        uint256 handleBefore = processor.handleCount();
        try gateway.retry(REMOTE_CENTRIFUGE_ID, message) {
            ghost_successfulRetries++;
            if (processor.handleCount() > handleBefore) {
                ghost_deliveries++;
            }
        } catch {}

        _after_();
    }

    /// @dev Repay an underpaid batch
    function gateway_repay(uint64 poolIdRaw) public {
        _before_();

        bytes memory message = _buildNotifyPoolMessage(poolIdRaw);
        bytes32 batchHash = keccak256(message);

        (, uint64 counterBefore) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);
        try gateway.repay{value: 0}(REMOTE_CENTRIFUGE_ID, message, address(this)) {
            ghost_underpaidRepaid++;
        } catch {}

        _after_();
    }

    /// @dev Exercise withBatch with lockCallback (correct flow)
    ///      BatchHelper calls gateway.send inside the callback, then lockCallback.
    function gateway_withBatch(uint64 poolIdRaw) public {
        _before_();

        bytes memory message = _buildNotifyPoolMessage(poolIdRaw);

        try batchHelper.startBatch(REMOTE_CENTRIFUGE_ID, message, true) {
            ghost_batchSuccesses++;
        } catch {}

        _after_();
    }

    /// @dev Exercise withBatch WITHOUT lockCallback (should revert with CallbackWasNotLocked)
    function gateway_withBatchNoLock(uint64 poolIdRaw) public {
        _before_();

        bytes memory message = _buildNotifyPoolMessage(poolIdRaw);

        try batchHelper.startBatch(REMOTE_CENTRIFUGE_ID, message, false) {
            // If this succeeds without lockCallback, that's a P-AGG-7 violation
            ghost_batchMissingLockCallback++;
        } catch {}

        _after_();
    }

    /// @dev Block/unblock outgoing for a pool
    function gateway_blockOutgoing(uint64 poolIdRaw, bool blocked) public {
        _before_();

        try gateway.blockOutgoing(REMOTE_CENTRIFUGE_ID, PoolId.wrap(poolIdRaw), blocked) {} catch {}

        _after_();
    }

    /// @dev Force a failed message by enabling processor failure, then delivering via quorum
    function gateway_createFailedMessage(uint64 poolIdRaw) public {
        _before_();

        // Enable failure mode
        processor.setShouldFail(true);

        bytes memory message = _buildNotifyPoolMessage(poolIdRaw);
        bytes32 messageHash = keccak256(message);

        uint256 failBefore = gateway.failedMessages(REMOTE_CENTRIFUGE_ID, messageHash);

        // Deliver via 2 adapters to reach quorum → gateway.handle → processor fails → failedMessages++
        try adapter0.deliver(REMOTE_CENTRIFUGE_ID, message) {} catch {}
        try adapter1.deliver(REMOTE_CENTRIFUGE_ID, message) {} catch {}

        uint256 failAfter = gateway.failedMessages(REMOTE_CENTRIFUGE_ID, messageHash);
        if (failAfter > failBefore) {
            ghost_failedMessages += (failAfter - failBefore);
        }

        // Disable failure mode for subsequent operations
        processor.setShouldFail(false);

        _after_();
    }

    /// @dev Create a failed message and then retry it
    function gateway_failAndRetry(uint64 poolIdRaw) public {
        _before_();

        bytes memory message = _buildNotifyPoolMessage(poolIdRaw);
        bytes32 messageHash = keccak256(message);

        // Phase 1: Create failure
        uint256 failBefore = gateway.failedMessages(REMOTE_CENTRIFUGE_ID, messageHash);
        processor.setShouldFail(true);
        try adapter0.deliver(REMOTE_CENTRIFUGE_ID, message) {} catch {}
        try adapter1.deliver(REMOTE_CENTRIFUGE_ID, message) {} catch {}
        processor.setShouldFail(false);

        uint256 failAfter = gateway.failedMessages(REMOTE_CENTRIFUGE_ID, messageHash);
        if (failAfter > failBefore) {
            ghost_failedMessages += (failAfter - failBefore);
        }

        // Phase 2: Retry
        uint256 handleBefore = processor.handleCount();
        try gateway.retry(REMOTE_CENTRIFUGE_ID, message) {
            ghost_successfulRetries++;
            if (processor.handleCount() > handleBefore) {
                ghost_deliveries++;
            }
        } catch {}

        _after_();
    }
}
