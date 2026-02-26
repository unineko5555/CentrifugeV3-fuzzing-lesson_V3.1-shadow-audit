// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {IAdapter} from "src/core/messaging/interfaces/IAdapter.sol";
import {IMessageHandler} from "src/core/messaging/interfaces/IMessageHandler.sol";

/// @title MockAdapter
/// @notice IAdapter stub for aggregator fuzzing.
///         Supports configurable estimate cost and a `deliver` helper to simulate
///         an adapter forwarding an incoming message to MultiAdapter.
contract MockAdapter is IAdapter {
    IMessageHandler public multiAdapter;
    uint256 public estimateCost;

    /// @dev Track sends for property assertions
    uint256 public sendCount;
    bytes public lastPayload;

    constructor(IMessageHandler multiAdapter_) {
        multiAdapter = multiAdapter_;
    }

    function setEstimateCost(uint256 cost) external {
        estimateCost = cost;
    }

    function send(uint16, bytes calldata payload, uint256, address)
        external
        payable
        returns (bytes32)
    {
        sendCount++;
        lastPayload = payload;
        return bytes32(0);
    }

    function estimate(uint16, bytes calldata, uint256) external view returns (uint256) {
        return estimateCost;
    }

    /// @notice Simulates adapter delivering a message (calls multiAdapter.handle as msg.sender = this adapter)
    function deliver(uint16 centrifugeId, bytes calldata payload) external {
        multiAdapter.handle(centrifugeId, payload);
    }
}
