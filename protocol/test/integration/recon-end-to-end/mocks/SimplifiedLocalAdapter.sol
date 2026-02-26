// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Auth} from "src/misc/Auth.sol";
import {IAdapter} from "src/core/messaging/interfaces/IAdapter.sol";
import {IMessageHandler} from "src/core/messaging/interfaces/IMessageHandler.sol";

/// @title SimplifiedLocalAdapter
/// @notice Simplified version of test/integration/adapters/LocalAdapter.sol for Echidna/Medusa.
///         Removes forge-std/Test.sol dependency, benchmarking, and vm.envOr.
///         Provides synchronous cross-chain message delivery for E2E fuzzing.
///
/// Usage:
///   adapterHubToSpoke = new SimplifiedLocalAdapter(HUB_ID, hubMultiAdapter, deployer);
///   adapterSpokeToHub = new SimplifiedLocalAdapter(SPOKE_ID, spokeMultiAdapter, deployer);
///   adapterHubToSpoke.setEndpoint(adapterSpokeToHub);
///   adapterSpokeToHub.setEndpoint(adapterHubToSpoke);
///
/// Message flow (Hub→Spoke):
///   hubMultiAdapter → adapterHubToSpoke.send() → adapterSpokeToHub.handle() → spokeMultiAdapter
contract SimplifiedLocalAdapter is Auth, IAdapter, IMessageHandler {
    uint16 public localCentrifugeId;
    IMessageHandler public entrypoint;
    IMessageHandler public endpoint;

    constructor(uint16 localCentrifugeId_, IMessageHandler entrypoint_, address deployer) Auth(deployer) {
        entrypoint = entrypoint_;
        localCentrifugeId = localCentrifugeId_;
    }

    function setEndpoint(IMessageHandler endpoint_) external auth {
        endpoint = endpoint_;
    }

    /// @inheritdoc IMessageHandler
    /// @dev Incoming message from the remote adapter → forward to local MultiAdapter
    function handle(uint16 remoteCentrifugeId, bytes calldata message) external {
        entrypoint.handle(remoteCentrifugeId, message);
    }

    /// @inheritdoc IAdapter
    /// @dev Outgoing message → deliver synchronously to remote adapter's handle()
    function send(uint16, bytes calldata payload, uint256, address refund)
        external
        payable
        returns (bytes32)
    {
        endpoint.handle(localCentrifugeId, payload);
        if (msg.value > 0) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success,) = payable(refund).call{value: msg.value}("");
            success; // silence unused variable warning
        }
        return bytes32("");
    }

    /// @inheritdoc IAdapter
    /// @dev Returns 0 — local adapter has no gas cost (synchronous delivery)
    function estimate(uint16, bytes calldata, uint256) external pure returns (uint256) {
        return 0;
    }
}
