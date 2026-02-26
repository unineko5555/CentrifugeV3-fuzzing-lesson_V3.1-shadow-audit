// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseSetup} from "@chimera/BaseSetup.sol";

import {Gateway} from "src/core/messaging/Gateway.sol";
import {MultiAdapter} from "src/core/messaging/MultiAdapter.sol";
import {GasService} from "src/core/messaging/GasService.sol";
import {IAdapter} from "src/core/messaging/interfaces/IAdapter.sol";
import {IMessageHandler} from "src/core/messaging/interfaces/IMessageHandler.sol";
import {IProtocolPauser} from "src/core/messaging/interfaces/IProtocolPauser.sol";
import {IMultiAdapter, MAX_ADAPTER_COUNT} from "src/core/messaging/interfaces/IMultiAdapter.sol";
import {PoolId} from "src/core/types/PoolId.sol";

import {MockAdapter} from "./mocks/MockAdapter.sol";
import {MockProcessor} from "./mocks/MockProcessor.sol";
import {MockProtocolPauser} from "./mocks/MockProtocolPauser.sol";
import {BatchHelper} from "./mocks/BatchHelper.sol";

/// @title Setup
/// @notice Deploys real Gateway + MultiAdapter + GasService with mock adapters and processor.
///         3 adapters, threshold=2, recoveryIndex=3 → exercises quorum voting (not fast-path).
abstract contract Setup is BaseSetup {
    // Constants
    uint16 constant LOCAL_CENTRIFUGE_ID = 1;
    uint16 constant REMOTE_CENTRIFUGE_ID = 2;
    PoolId constant GLOBAL_POOL = PoolId.wrap(0);

    // Real contracts
    Gateway public gateway;
    MultiAdapter public multiAdapter;
    GasService public gasService;

    // Mocks
    MockProcessor public processor;
    MockProtocolPauser public pauser;
    MockAdapter public adapter0;
    MockAdapter public adapter1;
    MockAdapter public adapter2;
    BatchHelper public batchHelper;

    // Accept ETH for gas payment tests
    fallback() external payable {}
    receive() external payable {}

    function setup() internal virtual override {
        // 1. Deploy GasService (fully immutable, no params)
        gasService = new GasService();

        // 2. Deploy MockProtocolPauser
        pauser = new MockProtocolPauser();

        // 3. Deploy real Gateway
        gateway = new Gateway(LOCAL_CENTRIFUGE_ID, IProtocolPauser(address(pauser)), address(this));

        // 4. Deploy MockProcessor
        processor = new MockProcessor();

        // 5. Deploy real MultiAdapter (gateway = IMessageHandler)
        multiAdapter = new MultiAdapter(LOCAL_CENTRIFUGE_ID, IMessageHandler(address(gateway)), address(this));

        // 6. Deploy 3 MockAdapters pointing to multiAdapter
        adapter0 = new MockAdapter(IMessageHandler(address(multiAdapter)));
        adapter1 = new MockAdapter(IMessageHandler(address(multiAdapter)));
        adapter2 = new MockAdapter(IMessageHandler(address(multiAdapter)));

        // 7. Wire Gateway dependencies
        gateway.file("processor", address(processor));
        gateway.file("adapter", address(multiAdapter));
        gateway.file("messageLimits", address(gasService));

        // 8. Wire MultiAdapter dependencies
        multiAdapter.file("messageProperties", address(processor));

        // 9. Set adapters: 3 adapters, threshold=2, recoveryIndex=3
        IAdapter[] memory adapters = new IAdapter[](3);
        adapters[0] = IAdapter(address(adapter0));
        adapters[1] = IAdapter(address(adapter1));
        adapters[2] = IAdapter(address(adapter2));
        multiAdapter.setAdapters(REMOTE_CENTRIFUGE_ID, GLOBAL_POOL, adapters, 2, 3);

        // 10. MultiAdapter must be ward on Gateway (it calls gateway.handle)
        gateway.rely(address(multiAdapter));

        // 11. Gateway must be ward on MultiAdapter (gateway calls multiAdapter.send for outgoing)
        multiAdapter.rely(address(gateway));

        // 12. Deploy BatchHelper for withBatch testing
        batchHelper = new BatchHelper(gateway);
        // BatchHelper needs ward on Gateway to call send
        gateway.rely(address(batchHelper));
    }

    // ===== Message Helpers ===== //

    /// @dev Build a NotifyPool message: [0x06][8 bytes poolId]
    ///      MessageType.NotifyPool = 6, length = 9 bytes
    function _buildNotifyPoolMessage(uint64 poolIdRaw) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(6), poolIdRaw);
    }

    /// @dev Build a ScheduleUpgrade message: [0x01][32 bytes address]
    ///      MessageType.ScheduleUpgrade = 1, length = 33 bytes
    ///      Pool-independent (messagePoolId returns 0)
    function _buildScheduleUpgradeMessage(address target) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(1), bytes32(uint256(uint160(target))));
    }

    /// @dev Get the mock adapters as an array
    function _getAdapters() internal view returns (MockAdapter[3] memory) {
        return [adapter0, adapter1, adapter2];
    }

    /// @dev Get adapter by index (clamped)
    function _getAdapter(uint8 idx) internal view returns (MockAdapter) {
        MockAdapter[3] memory adapters = _getAdapters();
        return adapters[idx % 3];
    }
}
