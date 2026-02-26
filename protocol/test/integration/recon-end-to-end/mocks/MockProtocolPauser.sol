// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {IProtocolPauser} from "src/core/messaging/interfaces/IProtocolPauser.sol";

/// @title MockProtocolPauser
/// @notice Minimal IProtocolPauser stub for E2E fuzzing Gateway deployment.
///         Not used by default (Root already implements IProtocolPauser), but available
///         if a lightweight standalone pauser is needed.
contract MockProtocolPauser is IProtocolPauser {
    bool public paused;

    function setPaused(bool _paused) external {
        paused = _paused;
        if (_paused) emit Pause();
        else emit Unpause();
    }
}
