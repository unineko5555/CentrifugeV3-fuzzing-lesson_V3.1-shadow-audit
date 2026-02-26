// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {IProtocolPauser} from "src/core/messaging/interfaces/IProtocolPauser.sol";

/// @title MockProtocolPauser
/// @notice Controllable IProtocolPauser for aggregator fuzzing.
contract MockProtocolPauser is IProtocolPauser {
    bool public paused;

    function setPaused(bool _paused) external {
        paused = _paused;
        if (_paused) emit Pause();
        else emit Unpause();
    }
}
