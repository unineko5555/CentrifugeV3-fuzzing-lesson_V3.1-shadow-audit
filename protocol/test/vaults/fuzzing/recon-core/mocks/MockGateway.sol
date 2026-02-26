// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

/// @title MockGateway for recon-core fuzzing
/// @notice Stub gateway that records messages and provides withBatch/lockCallback support
contract MockGateway {
    bytes[] public sentMessages;
    address private _batcher;
    bool private _isBatching;

    function send(uint16, bytes calldata message, uint128, address) external payable returns (bytes32) {
        sentMessages.push(message);
        return keccak256(message);
    }

    function withBatch(bytes memory data, address) external payable {
        _batcher = msg.sender;
        _isBatching = true;
        (bool success,) = msg.sender.call(data);
        require(success, "MockGateway: withBatch callback failed");
        _isBatching = false;
        _batcher = address(0);
    }

    function withBatch(bytes memory data, uint256, address) external payable {
        _batcher = msg.sender;
        _isBatching = true;
        (bool success,) = msg.sender.call(data);
        require(success, "MockGateway: withBatch callback failed");
        _isBatching = false;
        _batcher = address(0);
    }

    function lockCallback() external {
        // No-op for testing
    }

    function isBatching() external view returns (bool) {
        return _isBatching;
    }

    function setUnpaidMode(bool) external {
        // No-op
    }

    function estimate(uint16, bytes calldata, uint128) external pure returns (uint256) {
        return 0;
    }

    function topUp(uint64) external payable {
        // No-op
    }

    function subsidizePool(uint64) external payable {
        // No-op
    }

    function appendToBatch(uint16, uint64, bytes calldata message, uint128) external {
        sentMessages.push(message);
    }

    function sentMessageCount() external view returns (uint256) {
        return sentMessages.length;
    }

    fallback() external payable {}
    receive() external payable {}
}
