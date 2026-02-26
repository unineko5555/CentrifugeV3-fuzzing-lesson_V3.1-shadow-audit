// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {TargetFunctions} from "./TargetFunctions.sol";
import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";
import {Test} from "forge-std/Test.sol";

import {PoolId} from "src/core/types/PoolId.sol";
import {IAdapter} from "src/core/messaging/interfaces/IAdapter.sol";

/// @title CryticToFoundry
/// @notice Foundry smoke tests for the recon-aggregator fuzzing suite.
contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    function setUp() public {
        setup();
    }

    // ===================================================================
    // Setup Verification
    // ===================================================================

    function test_setup_deploys_correctly() public view {
        assertTrue(address(gateway) != address(0), "Gateway deployed");
        assertTrue(address(multiAdapter) != address(0), "MultiAdapter deployed");
        assertTrue(address(gasService) != address(0), "GasService deployed");
        assertTrue(address(processor) != address(0), "Processor deployed");
        assertTrue(address(pauser) != address(0), "Pauser deployed");
        assertTrue(address(adapter0) != address(0), "Adapter0 deployed");
        assertTrue(address(adapter1) != address(0), "Adapter1 deployed");
        assertTrue(address(adapter2) != address(0), "Adapter2 deployed");
    }

    function test_wiring_correct() public view {
        assertEq(address(gateway.adapter()), address(multiAdapter), "Gateway.adapter = multiAdapter");
        assertEq(address(gateway.processor()), address(processor), "Gateway.processor = processor");
        assertEq(address(gateway.messageLimits()), address(gasService), "Gateway.messageLimits = gasService");
        assertEq(gateway.wards(address(multiAdapter)), 1, "MultiAdapter is ward on Gateway");
    }

    function test_adapter_config() public view {
        uint8 quorum = multiAdapter.quorum(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        uint8 threshold = multiAdapter.threshold(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        uint8 recoveryIdx = multiAdapter.recoveryIndex(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);

        assertEq(quorum, 3, "Quorum should be 3 (3 adapters)");
        assertEq(threshold, 2, "Threshold should be 2");
        assertEq(recoveryIdx, 3, "Recovery index should be 3");
    }

    // ===================================================================
    // Quorum Voting
    // ===================================================================

    function test_single_adapter_below_threshold() public {
        bytes memory message = _buildNotifyPoolMessage(1);

        uint256 handleBefore = processor.handleCount();
        adapter0.deliver(REMOTE_CENTRIFUGE_ID, message);

        // Threshold=2, only 1 vote → no delivery
        assertEq(processor.handleCount(), handleBefore, "Single vote should not deliver");
    }

    function test_quorum_reached_delivers() public {
        bytes memory message = _buildNotifyPoolMessage(1);

        uint256 handleBefore = processor.handleCount();

        // 2 different adapters vote → threshold=2 met
        adapter0.deliver(REMOTE_CENTRIFUGE_ID, message);
        adapter1.deliver(REMOTE_CENTRIFUGE_ID, message);

        assertEq(processor.handleCount(), handleBefore + 1, "Quorum should trigger delivery");
        assertEq(processor.lastCentrifugeId(), REMOTE_CENTRIFUGE_ID, "CentrifugeId should match");
    }

    function test_double_vote_same_adapter() public {
        bytes memory message = _buildNotifyPoolMessage(2);

        uint256 handleBefore = processor.handleCount();

        // Same adapter votes twice → should NOT reach threshold
        adapter0.deliver(REMOTE_CENTRIFUGE_ID, message);
        adapter0.deliver(REMOTE_CENTRIFUGE_ID, message);

        // countPositiveValues counts distinct positive slots
        // adapter0 is slot 0, voting twice makes slot[0] = 2
        // Still only 1 positive slot, threshold=2 not met
        assertEq(processor.handleCount(), handleBefore, "Double vote should not deliver");
    }

    // ===================================================================
    // Session Reset
    // ===================================================================

    function test_session_reset_clears_votes() public {
        bytes memory message = _buildNotifyPoolMessage(3);

        // Adapter0 votes
        adapter0.deliver(REMOTE_CENTRIFUGE_ID, message);

        // Reconfigure adapters (same set, triggers session increment)
        IAdapter[] memory adapters = new IAdapter[](3);
        adapters[0] = IAdapter(address(adapter0));
        adapters[1] = IAdapter(address(adapter1));
        adapters[2] = IAdapter(address(adapter2));
        multiAdapter.setAdapters(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, adapters, 2, 3);

        // Now adapter1 votes on same message — votes from adapter0 are cleared
        uint256 handleBefore = processor.handleCount();
        adapter1.deliver(REMOTE_CENTRIFUGE_ID, message);

        // Only 1 vote in new session → no delivery
        assertEq(processor.handleCount(), handleBefore, "Stale vote should be cleared");

        // Now adapter0 votes again in new session → 2 votes → deliver
        adapter0.deliver(REMOTE_CENTRIFUGE_ID, message);
        assertEq(processor.handleCount(), handleBefore + 1, "Fresh quorum should deliver");
    }

    // ===================================================================
    // Failed Messages & Retry
    // ===================================================================

    function test_failed_message_retry() public {
        bytes memory message = _buildNotifyPoolMessage(4);
        bytes32 messageHash = keccak256(message);

        // Enable failure
        processor.setShouldFail(true);

        // Deliver via quorum → handle fails → failedMessages++
        adapter0.deliver(REMOTE_CENTRIFUGE_ID, message);
        adapter1.deliver(REMOTE_CENTRIFUGE_ID, message);

        uint256 failCount = gateway.failedMessages(REMOTE_CENTRIFUGE_ID, messageHash);
        assertEq(failCount, 1, "Failed message should be recorded");

        // Disable failure
        processor.setShouldFail(false);

        // Retry
        uint256 handleBefore = processor.handleCount();
        gateway.retry(REMOTE_CENTRIFUGE_ID, message);

        assertEq(processor.handleCount(), handleBefore + 1, "Retry should deliver");
        assertEq(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, messageHash), 0, "Failed counter should be 0");
    }

    // ===================================================================
    // Pause
    // ===================================================================

    function test_paused_blocks_handle() public {
        pauser.setPaused(true);

        bytes memory message = _buildNotifyPoolMessage(5);

        // Direct handle should fail (paused)
        vm.expectRevert();
        gateway.handle(REMOTE_CENTRIFUGE_ID, message);

        pauser.setPaused(false);
    }

    // ===================================================================
    // Outgoing Blocked
    // ===================================================================

    function test_outgoing_blocked() public {
        PoolId testPool = PoolId.wrap(uint64(10));
        bytes memory message = _buildNotifyPoolMessage(10);

        // Block outgoing for this pool
        gateway.blockOutgoing(REMOTE_CENTRIFUGE_ID, testPool, true);
        assertTrue(gateway.isOutgoingBlocked(REMOTE_CENTRIFUGE_ID, testPool), "Should be blocked");

        // Enable unpaid mode so we don't revert on gas
        gateway.setUnpaidMode(true);

        // Try to send — should revert with OutgoingBlocked
        vm.expectRevert();
        gateway.send{value: 0}(REMOTE_CENTRIFUGE_ID, message, 0, address(this));

        // Unblock
        gateway.blockOutgoing(REMOTE_CENTRIFUGE_ID, testPool, false);
        gateway.setUnpaidMode(false);
    }

    // ===================================================================
    // Batch Lifecycle
    // ===================================================================

    function test_batch_with_lock_callback() public {
        bytes memory message = _buildNotifyPoolMessage(20);

        uint256 sendCountBefore = adapter0.sendCount() + adapter1.sendCount() + adapter2.sendCount();

        // BatchHelper.startBatch calls gateway.withBatch → callback → send + lockCallback
        batchHelper.startBatch(REMOTE_CENTRIFUGE_ID, message, true);

        uint256 sendCountAfter = adapter0.sendCount() + adapter1.sendCount() + adapter2.sendCount();
        // The batched message should have been sent through adapters
        assertGt(sendCountAfter, sendCountBefore, "Batch should have sent through adapters");
    }

    function test_batch_without_lock_callback_reverts() public {
        bytes memory message = _buildNotifyPoolMessage(21);

        // BatchHelper.startBatch with callLock=false → withBatch reverts with CallbackWasNotLocked
        vm.expectRevert();
        batchHelper.startBatch(REMOTE_CENTRIFUGE_ID, message, false);
    }

    function test_stale_session_delivery() public {
        bytes memory message = _buildNotifyPoolMessage(22);

        // Phase 1: adapter0 votes
        adapter0.deliver(REMOTE_CENTRIFUGE_ID, message);

        // Phase 2: reconfigure (session++)
        IAdapter[] memory adapters = new IAdapter[](3);
        adapters[0] = IAdapter(address(adapter0));
        adapters[1] = IAdapter(address(adapter1));
        adapters[2] = IAdapter(address(adapter2));
        multiAdapter.setAdapters(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, adapters, 2, 3);

        // Phase 3: adapter1 votes in new session — only 1 fresh vote, should NOT deliver
        uint256 handleBefore = processor.handleCount();
        adapter1.deliver(REMOTE_CENTRIFUGE_ID, message);
        assertEq(processor.handleCount(), handleBefore, "Stale vote + 1 fresh should not deliver");
    }

    // ===================================================================
    // Unpaid Mode & Repay
    // ===================================================================

    function test_unpaid_mode_and_repay() public {
        // Set adapter estimate cost > 0 so messages become underpaid
        adapter0.setEstimateCost(1 ether);
        adapter1.setEstimateCost(1 ether);
        adapter2.setEstimateCost(1 ether);

        gateway.setUnpaidMode(true);

        bytes memory message = _buildNotifyPoolMessage(30);
        bytes32 batchHash = keccak256(message);

        // Send without enough value → underpaid counter++
        gateway.send{value: 0}(REMOTE_CENTRIFUGE_ID, message, 0, address(this));

        // Verify underpaid (struct is { uint128 gasLimit; uint64 counter; })
        (, uint64 counter) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);
        assertEq(counter, 1, "Underpaid counter should be 1");

        gateway.setUnpaidMode(false);

        // Reset estimate costs
        adapter0.setEstimateCost(0);
        adapter1.setEstimateCost(0);
        adapter2.setEstimateCost(0);

        // Repay the underpaid batch
        gateway.repay{value: 0}(REMOTE_CENTRIFUGE_ID, message, address(this));

        (, counter) = gateway.underpaid(REMOTE_CENTRIFUGE_ID, batchHash);
        assertEq(counter, 0, "Underpaid counter should be 0 after repay");
    }
}
