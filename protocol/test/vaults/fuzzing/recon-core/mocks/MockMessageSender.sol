// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

/// @title MockMessageSender for recon-core fuzzing
/// @notice Minimal mock for ISpokeMessageSender — stubs all cross-chain send operations.
///         Spoke.sender is set to this address; all outgoing messages are no-ops.
contract MockMessageSender {
    uint16 internal _localCentrifugeId;

    constructor(uint16 centrifugeId_) {
        _localCentrifugeId = centrifugeId_;
    }

    /// @dev Required by Spoke.registerAsset and crosschainTransferShares
    function localCentrifugeId() external view returns (uint16) {
        return _localCentrifugeId;
    }

    /// @dev Accept all other calls (sendRequest, sendRegisterAsset, etc.) as no-ops
    fallback() external payable {}

    receive() external payable {}
}
