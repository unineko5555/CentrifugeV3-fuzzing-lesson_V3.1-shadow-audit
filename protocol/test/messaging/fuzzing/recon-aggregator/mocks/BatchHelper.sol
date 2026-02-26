// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Gateway} from "src/core/messaging/Gateway.sol";

/// @title BatchHelper
/// @notice Helper contract that acts as msg.sender for gateway.withBatch.
///         withBatch calls msg.sender back with data; this contract then
///         calls gateway.send + gateway.lockCallback within the callback.
contract BatchHelper {
    Gateway public gateway;
    bool public shouldCallLockCallback;
    uint16 public sendCentrifugeId;
    bytes public sendMessage;

    constructor(Gateway gateway_) {
        gateway = gateway_;
        shouldCallLockCallback = true;
    }

    /// @dev Configure what to send during the batch callback
    function configureBatch(uint16 centrifugeId, bytes calldata message, bool callLock) external {
        sendCentrifugeId = centrifugeId;
        sendMessage = message;
        shouldCallLockCallback = callLock;
    }

    /// @dev Called by gateway.withBatch as the callback (msg.sender = gateway)
    ///      This function calls gateway.send to enqueue a message in the batch,
    ///      then calls gateway.lockCallback to signal completion.
    function executeBatch() external {
        // Send a message (will be batched since isBatching is true)
        gateway.send{value: 0}(sendCentrifugeId, sendMessage, 0, address(this));

        // Lock the callback (required by withBatch)
        if (shouldCallLockCallback) {
            gateway.lockCallback();
        }
    }

    /// @dev Initiate a withBatch call on the gateway
    function startBatch(uint16 centrifugeId, bytes calldata message, bool callLock) external {
        sendCentrifugeId = centrifugeId;
        sendMessage = message;
        shouldCallLockCallback = callLock;

        bytes memory callbackData = abi.encodeCall(this.executeBatch, ());
        gateway.withBatch(callbackData, 0, address(this));
    }

    // Accept ETH refunds
    receive() external payable {}
    fallback() external payable {}
}
