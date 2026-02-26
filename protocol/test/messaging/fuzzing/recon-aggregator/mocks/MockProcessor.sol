// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {IMessageHandler} from "src/core/messaging/interfaces/IMessageHandler.sol";
import {IMessageProperties} from "src/core/messaging/interfaces/IMessageProperties.sol";
import {MessageLib, MessageType} from "src/core/messaging/libraries/MessageLib.sol";
import {PoolId} from "src/core/types/PoolId.sol";

/// @title MockProcessor
/// @notice Implements IGatewayProcessor (IMessageHandler + IMessageProperties).
///         Delegates messageLength/messagePoolId to real MessageLib for fidelity.
///         Tracks handle invocations for property assertions.
contract MockProcessor is IMessageHandler, IMessageProperties {
    using MessageLib for bytes;

    /// @dev Configurable: if true, handle reverts (to test failed message path)
    bool public shouldFail;

    /// @dev Track successful handle invocations
    uint256 public handleCount;
    bytes public lastMessage;
    uint16 public lastCentrifugeId;

    function setShouldFail(bool fail) external {
        shouldFail = fail;
    }

    function handle(uint16 centrifugeId, bytes calldata message) external {
        if (shouldFail) revert("MockProcessor: forced failure");
        handleCount++;
        lastCentrifugeId = centrifugeId;
        lastMessage = message;
    }

    /// @dev Delegate to real MessageLib — ensures Gateway batch iteration matches production
    function messageLength(bytes calldata message) external pure returns (uint16) {
        return MessageLib.messageLength(message);
    }

    /// @dev Delegate to real MessageLib — ensures pool routing matches production
    function messagePoolId(bytes calldata message) external pure returns (PoolId) {
        return MessageLib.messagePoolId(message);
    }
}
