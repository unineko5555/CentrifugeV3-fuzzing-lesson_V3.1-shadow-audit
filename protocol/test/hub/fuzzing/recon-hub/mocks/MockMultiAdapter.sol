// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {IAdapter} from "src/core/messaging/interfaces/IAdapter.sol";
import {PoolId} from "src/core/types/PoolId.sol";

/// @title MockMultiAdapter
/// @notice Minimal mock of IMultiAdapter for recon-hub fuzzing.
///         Stubs out multi-adapter logic since we don't need real cross-chain in hub-level fuzzing.
contract MockMultiAdapter {
    function send(uint16, bytes calldata, uint256, address) external payable returns (bytes32) {
        return bytes32(0);
    }

    function estimate(uint16, bytes calldata, uint256 baseCost) external pure returns (uint256) {
        return baseCost;
    }

    function handle(uint16, bytes calldata) external {}

    function wire(bytes memory) external pure {}

    function isWired(uint16) external pure returns (bool) {
        return true;
    }

    function file(bytes32, address) external {}

    function setAdapters(uint16, PoolId, IAdapter[] calldata, uint8, uint8) external {}

    function quorum(uint16, PoolId) external pure returns (uint8) {
        return 1;
    }

    function threshold(uint16, PoolId) external pure returns (uint8) {
        return 1;
    }

    function recoveryIndex(uint16, PoolId) external pure returns (uint8) {
        return 1;
    }

    function activeSessionId(uint16, PoolId) external pure returns (uint64) {
        return 0;
    }

    function votes(uint16, bytes32) external pure returns (int16[8] memory) {
        int16[8] memory v;
        return v;
    }

    function adapters(uint16, PoolId, uint256) external view returns (IAdapter) {
        return IAdapter(address(this));
    }

    function poolAdapters(uint16, PoolId) external view returns (IAdapter[] memory) {
        IAdapter[] memory a = new IAdapter[](1);
        a[0] = IAdapter(address(this));
        return a;
    }

    receive() external payable {}
}
