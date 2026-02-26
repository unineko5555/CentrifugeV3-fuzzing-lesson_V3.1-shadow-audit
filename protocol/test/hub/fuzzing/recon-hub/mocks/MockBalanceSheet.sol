// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

/// @title MockBalanceSheet
/// @notice Minimal mock for BalanceSheet in hub fuzzing.
///         All functions are no-ops since hub-level fuzzing doesn't exercise balance sheet logic.
contract MockBalanceSheet {
    function deposit(uint64, bytes16, address, uint256, address, uint128) external {}
    function withdraw(uint64, bytes16, address, uint256, address, uint128) external {}
    function issue(uint64, bytes16, address, uint128) external {}
    function revoke(uint64, bytes16, address, uint128) external {}
    function noteDeposit(uint64, bytes16, address, uint256, address, uint128) external {}
    function noteRevoke(uint64, bytes16, address, uint128) external {}
    function triggerDeposit(uint64, bytes16, uint128, address, uint128) external {}
    function triggerIssueShares(uint64, bytes16, address, uint128) external {}
    function triggerWithdraw(uint64, bytes16, uint128, address, uint128) external {}
    function submitQueuedAssets(uint64, bytes16, uint128) external {}
    function submitQueuedShares(uint64, bytes16) external {}
    function overridePricePoolPerAsset(uint64, bytes16, uint128, uint128) external {}
    function overridePricePoolPerShare(uint64, bytes16, uint128) external {}
    function transferSharesFrom(uint64, bytes16, address, address, uint256) external {}
    function setQueue(uint64, bytes16, bool) external {}
    function update(uint64, bytes16, bytes memory) external {}
    function file(bytes32, address) external {}
    function rely(address) external {}
    function deny(address) external {}
    function recoverTokens(address, address, uint256) external {}
    function recoverTokens(address, uint256, address, uint256) external {}

    receive() external payable {}
}
