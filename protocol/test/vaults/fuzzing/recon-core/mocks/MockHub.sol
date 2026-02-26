// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

/// @title MockHub for recon-core fuzzing
/// @notice Minimal stub — spoke-side doesn't call hub directly, only via gateway messages.
///         Accepts any call via fallback so that gateway message forwarding never reverts.
contract MockHub {
    fallback() external payable {}
    receive() external payable {}
}
