// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

/// @title MockSpoke
/// @notice Minimal mock for spoke-side operations in hub fuzzing.
///         All functions are no-ops since hub-level fuzzing doesn't exercise spoke logic.
contract MockSpoke {
    function addPool(uint64) external {}
    function addShareClass(uint64, bytes16, string memory, string memory, uint8, bytes32, address) external {}
    function handleTransferShares(uint64, bytes16, address, uint128) external {}
    function linkVault(uint64, bytes16, uint128, address) external {}
    function unlinkVault(uint64, bytes16, uint128, address) external {}
    function update(uint64, bytes16, bytes memory) external {}
    function updateContract(uint64, bytes16, address, bytes memory) external {}
    function updatePricePoolPerAsset(uint64, bytes16, uint128, uint128, uint64) external {}
    function updatePricePoolPerShare(uint64, bytes16, uint128, uint64) external {}
    function updateRestriction(uint64, bytes16, bytes memory) external {}
    function updateShareHook(uint64, bytes16, address) external {}
    function updateShareMetadata(uint64, bytes16, string memory, string memory) external {}
    function file(bytes32, address) external {}
    function rely(address) external {}
    function deny(address) external {}

    receive() external payable {}
}
