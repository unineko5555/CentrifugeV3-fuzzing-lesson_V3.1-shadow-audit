// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";
import {Properties} from "../properties/Properties.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title HubNotificationTargets
/// @notice Target functions for Hub cross-chain notification messages.
///         Exercises Hub.notifySharePrice, notifyAssetPrice, notifyShareMetadata, updateShareHook
///         which send messages via MessageDispatcher to the spoke-side handlers.
abstract contract HubNotificationTargets is BaseTargetFunctions, Properties {
    using CastLib for *;

    /// @dev Hub.notifySharePrice → sends price to spoke via MessageDispatcher
    function hub_notifySharePrice()
        public
        updateGhostsWithType(OpType.HUB_NOTIFY_PRICE)
        poolExists
    {
        try hub.notifySharePrice(
            activePoolId, activeScId, SPOKE_CENTRIFUGE_ID, address(this)
        ) {} catch {}
    }

    /// @dev Hub.notifyAssetPrice → sends asset price to spoke (+ feeHook.accrue check)
    function hub_notifyAssetPrice()
        public
        updateGhostsWithType(OpType.HUB_NOTIFY_PRICE)
        poolExists
    {
        try hub.notifyAssetPrice(
            activePoolId, activeScId, activeAssetId, address(this)
        ) {} catch {}
    }

    /// @dev Hub.notifyShareMetadata → sends name/symbol to spoke
    function hub_notifyShareMetadata()
        public
        updateGhostsWithType(OpType.HUB_NOTIFY_METADATA)
        poolExists
    {
        try hub.notifyShareMetadata(
            activePoolId, activeScId, SPOKE_CENTRIFUGE_ID, address(this)
        ) {} catch {}
    }

    /// @dev Hub.updateShareHook → update hook on spoke (re-set fullRestrictions)
    function hub_updateShareHook()
        public
        updateGhostsWithType(OpType.HUB_NOTIFY_METADATA)
        poolExists
    {
        try hub.updateShareHook(
            activePoolId, activeScId, SPOKE_CENTRIFUGE_ID,
            CastLib.toBytes32(address(fullRestrictions)),
            address(this)
        ) {} catch {}
    }
}
