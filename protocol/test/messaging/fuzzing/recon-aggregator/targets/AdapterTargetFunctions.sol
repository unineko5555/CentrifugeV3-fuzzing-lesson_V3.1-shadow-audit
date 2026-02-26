// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Properties} from "../Properties.sol";
import {MockAdapter} from "../mocks/MockAdapter.sol";
import {IAdapter} from "src/core/messaging/interfaces/IAdapter.sol";
import {PoolId} from "src/core/types/PoolId.sol";

/// @title AdapterTargetFunctions
/// @notice Target functions simulating incoming message delivery via adapters.
///         Exercises MultiAdapter quorum voting, double-vote, session management.
abstract contract AdapterTargetFunctions is Properties {
    /// @dev Single adapter delivers a NotifyPool message
    function adapter_deliver(uint8 adapterIdx, uint64 poolIdRaw) public {
        _before_();

        MockAdapter adapter = _getAdapter(adapterIdx);
        bytes memory message = _buildNotifyPoolMessage(poolIdRaw);
        bytes32 messageHash = keccak256(message);

        // Track ghost vote
        ghost_adapterVotes[address(adapter)][messageHash]++;

        uint256 handleBefore = processor.handleCount();
        try adapter.deliver(REMOTE_CENTRIFUGE_ID, message) {} catch {}

        if (processor.handleCount() > handleBefore) {
            ghost_deliveries++;
        }

        _after_();
    }

    /// @dev Same adapter delivers same message twice (tests double-vote behavior)
    ///      With threshold >= 2, this must NOT trigger delivery.
    function adapter_deliverDuplicate(uint8 adapterIdx, uint64 poolIdRaw) public {
        _before_();

        MockAdapter adapter = _getAdapter(adapterIdx);
        bytes memory message = _buildNotifyPoolMessage(poolIdRaw);
        bytes32 messageHash = keccak256(message);

        ghost_adapterVotes[address(adapter)][messageHash] += 2;
        ghost_lastDuplicateHash = messageHash;

        uint256 handleBefore = processor.handleCount();
        try adapter.deliver(REMOTE_CENTRIFUGE_ID, message) {} catch {}
        try adapter.deliver(REMOTE_CENTRIFUGE_ID, message) {} catch {}

        uint256 newDeliveries = processor.handleCount() - handleBefore;
        ghost_deliveries += newDeliveries;

        // Record if this single adapter's duplicate votes caused delivery
        // Only flag when threshold >= 2, since with threshold=1 delivery is expected.
        uint8 threshold = multiAdapter.threshold(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        if (newDeliveries > 0 && threshold >= 2) {
            ghost_singleAdapterDelivered[address(adapter)][messageHash] = true;
        }

        _after_();
    }

    /// @dev All 3 adapters deliver the same message (tests quorum with threshold=2)
    function adapter_deliverFromMultiple(uint64 poolIdRaw) public {
        _before_();

        bytes memory message = _buildNotifyPoolMessage(poolIdRaw);
        bytes32 messageHash = keccak256(message);

        ghost_adapterVotes[address(adapter0)][messageHash]++;
        ghost_adapterVotes[address(adapter1)][messageHash]++;
        ghost_adapterVotes[address(adapter2)][messageHash]++;

        uint256 handleBefore = processor.handleCount();

        try adapter0.deliver(REMOTE_CENTRIFUGE_ID, message) {} catch {}
        try adapter1.deliver(REMOTE_CENTRIFUGE_ID, message) {} catch {}
        try adapter2.deliver(REMOTE_CENTRIFUGE_ID, message) {} catch {}

        uint256 newDeliveries = processor.handleCount() - handleBefore;
        ghost_deliveries += newDeliveries;

        _after_();
    }

    /// @dev Deliver after a session reset — old votes should be invalidated.
    ///      Adapter0 votes, then reconfigure (session++), then adapter1 votes.
    ///      With threshold=2, only adapter1's fresh vote exists → no delivery.
    function adapter_deliverWithStaleSession(uint64 poolIdRaw) public {
        _before_();

        bytes memory message = _buildNotifyPoolMessage(poolIdRaw);
        bytes32 messageHash = keccak256(message);

        // Phase 1: adapter0 votes in current session
        ghost_adapterVotes[address(adapter0)][messageHash]++;
        try adapter0.deliver(REMOTE_CENTRIFUGE_ID, message) {} catch {}

        // Phase 2: reconfigure adapters (triggers session increment)
        IAdapter[] memory adapters = new IAdapter[](3);
        adapters[0] = IAdapter(address(adapter0));
        adapters[1] = IAdapter(address(adapter1));
        adapters[2] = IAdapter(address(adapter2));
        try multiAdapter.setAdapters(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, adapters, 2, 3) {
            ghost_lastSessionId = multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        } catch {}

        // Phase 3: adapter1 votes in new session — only 1 fresh vote, should NOT deliver
        uint256 handleBefore = processor.handleCount();
        ghost_adapterVotes[address(adapter1)][messageHash]++;
        try adapter1.deliver(REMOTE_CENTRIFUGE_ID, message) {} catch {}

        if (processor.handleCount() > handleBefore) {
            ghost_deliveries++;
        }

        _after_();
    }

    /// @dev Deliver with only 1 adapter (below threshold=2, should NOT deliver to processor)
    function adapter_deliverBelowThreshold(uint8 adapterIdx, uint64 poolIdRaw) public {
        _before_();

        MockAdapter adapter = _getAdapter(adapterIdx);
        bytes memory message = _buildNotifyPoolMessage(poolIdRaw);
        bytes32 messageHash = keccak256(message);

        ghost_adapterVotes[address(adapter)][messageHash]++;

        uint256 handleBefore = processor.handleCount();
        try adapter.deliver(REMOTE_CENTRIFUGE_ID, message) {} catch {}

        if (processor.handleCount() > handleBefore) {
            ghost_deliveries++;
        }

        _after_();
    }
}
