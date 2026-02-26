// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

/// @title MockGateway
/// @notice Minimal mock of IGateway for recon-hub fuzzing.
///         Supports withBatch/lockCallback flow required by BatchedMulticall,
///         while stubbing out real cross-chain message dispatch.
contract MockGateway {
    address private _batcher;
    bool public isBatching;

    // Record messages for inspection
    bytes[] public sentMessages;

    /// @dev Called by BatchedMulticall.multicall → gateway.withBatch(data, refund)
    function withBatch(bytes memory data, address /* refund */) external payable {
        withBatch(data, 0, msg.sender);
    }

    function withBatch(bytes memory data, uint256 callbackValue, address /* refund */) public payable {
        bool isNested = isBatching;
        isBatching = true;
        _batcher = msg.sender;

        (bool success, bytes memory returnData) = msg.sender.call{value: callbackValue}(data);
        if (!success) {
            uint256 length = returnData.length;
            if (length == 0) revert("MockGateway: call failed");
            assembly ("memory-safe") {
                revert(add(32, returnData), length)
            }
        }

        // BatchedMulticall must call lockCallback before returning
        require(_batcher == address(0), "MockGateway: callback not locked");

        if (!isNested) {
            isBatching = false;
        }
    }

    function lockCallback() external {
        require(_batcher != address(0), "MockGateway: callback already locked");
        require(msg.sender == _batcher, "MockGateway: not batcher");
        _batcher = address(0);
    }

    /// @dev Stub: record outgoing message bytes
    function send(uint16, bytes calldata message, uint256, address) external payable returns (bytes32) {
        sentMessages.push(message);
        return bytes32(0);
    }

    /// @dev Stub: no-op for subsidy
    function subsidizePool(uint64) external payable {}

    /// @dev Stub: estimate returns 0
    function estimate(uint16, bytes calldata, uint256) external pure returns (uint256) {
        return 0;
    }

    /// @dev Stub: accept topUp
    function topUp(uint64) external payable {}

    /// @dev Stub: batch append (called by Hub.sender when batching)
    function appendToBatch(uint16, uint64, bytes calldata message, uint128) external {
        sentMessages.push(message);
    }

    function sentMessageCount() external view returns (uint256) {
        return sentMessages.length;
    }

    receive() external payable {}
}
