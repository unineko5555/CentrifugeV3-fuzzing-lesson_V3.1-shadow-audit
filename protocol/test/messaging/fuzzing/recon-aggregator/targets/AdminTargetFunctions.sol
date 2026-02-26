// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Properties} from "../Properties.sol";
import {IAdapter} from "src/core/messaging/interfaces/IAdapter.sol";
import {PoolId} from "src/core/types/PoolId.sol";

/// @title AdminTargetFunctions
/// @notice Target functions for adapter reconfiguration, pause control, and admin operations.
abstract contract AdminTargetFunctions is Properties {
    /// @dev Reconfigure adapters with new threshold (triggers session increment, invalidates votes)
    function admin_reconfigureAdapters(uint8 newThreshold) public {
        _before_();

        // Clamp threshold to [1, 3]
        uint8 threshold = (newThreshold % 3) + 1;

        IAdapter[] memory adapters = new IAdapter[](3);
        adapters[0] = IAdapter(address(adapter0));
        adapters[1] = IAdapter(address(adapter1));
        adapters[2] = IAdapter(address(adapter2));

        try multiAdapter.setAdapters(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, adapters, threshold, 3) {
            // Session was incremented — record for properties
            ghost_lastSessionId = multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        } catch {}

        _after_();
    }

    /// @dev Reconfigure with fewer adapters (e.g., 2 adapters, threshold=1 → quorum=1 fast path)
    function admin_reconfigureTwoAdapters() public {
        _before_();

        IAdapter[] memory adapters = new IAdapter[](2);
        adapters[0] = IAdapter(address(adapter0));
        adapters[1] = IAdapter(address(adapter1));

        try multiAdapter.setAdapters(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, adapters, 1, 2) {
            ghost_lastSessionId = multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        } catch {}

        _after_();
    }

    /// @dev Reconfigure with single adapter (quorum=1, fast path)
    function admin_reconfigureSingleAdapter() public {
        _before_();

        IAdapter[] memory adapters = new IAdapter[](1);
        adapters[0] = IAdapter(address(adapter0));

        try multiAdapter.setAdapters(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, adapters, 1, 1) {
            ghost_lastSessionId = multiAdapter.activeSessionId(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL);
        } catch {}

        _after_();
    }

    /// @dev Pause the protocol
    function admin_pause() public {
        _before_();
        pauser.setPaused(true);
        _after_();
    }

    /// @dev Unpause the protocol
    function admin_unpause() public {
        _before_();
        pauser.setPaused(false);
        _after_();
    }

    /// @dev Set per-pool adapter configuration (not global)
    function admin_setPoolAdapters(uint64 poolIdRaw, uint8 newThreshold) public {
        _before_();

        uint8 threshold = (newThreshold % 3) + 1;

        IAdapter[] memory adapters = new IAdapter[](3);
        adapters[0] = IAdapter(address(adapter0));
        adapters[1] = IAdapter(address(adapter1));
        adapters[2] = IAdapter(address(adapter2));

        try multiAdapter.setAdapters(REMOTE_CENTRIFUGE_ID, PoolId.wrap(poolIdRaw), adapters, threshold, 3) {}
        catch {}

        _after_();
    }
}
