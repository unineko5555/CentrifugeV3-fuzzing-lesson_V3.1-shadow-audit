// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

/// @title MockMessageSender
/// @notice Minimal mock for IHubMessageSender — stubs all cross-chain send operations.
///         Hub.sender is set to this address; all outgoing messages are no-ops.
contract MockMessageSender {
    uint16 internal _localCentrifugeId;

    constructor(uint16 centrifugeId_) {
        _localCentrifugeId = centrifugeId_;
    }

    /// @dev Required by Hub.createPool — called as staticcall (view)
    function localCentrifugeId() external view returns (uint16) {
        return _localCentrifugeId;
    }

    /// @dev Accept all other calls (send* functions) as no-ops
    fallback() external payable {}

    receive() external payable {}
}
