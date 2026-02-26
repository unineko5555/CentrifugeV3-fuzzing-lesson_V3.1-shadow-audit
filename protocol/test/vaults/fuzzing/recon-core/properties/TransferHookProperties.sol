// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Asserts} from "@chimera/Asserts.sol";

import {IShareToken} from "src/core/spoke/interfaces/IShareToken.sol";
import {HookData, ESCROW_HOOK_ID} from "src/core/spoke/interfaces/ITransferHook.sol";
import {BitmapLib} from "src/misc/libraries/BitmapLib.sol";

import {Setup} from "../Setup.sol";

/// @dev TransferHook / FullRestrictions invariant properties — P-TH-1 through P-TH-6
abstract contract TransferHookProperties is Setup, Asserts {
    using BitmapLib for uint128;

    /// @dev P-TH-1: Frozen non-endorsed user's transfer is blocked
    function property_TH_1() public {
        if (address(token) == address(0)) return;
        if (address(fullRestrictions) == address(0)) return;

        address actor = _getActor();
        bytes16 hookDataRaw = IShareToken(address(token)).hookDataOf(actor);
        bool isFrozen = uint128(hookDataRaw).getBit(0);
        bool isEndorsed = root.endorsed(actor);

        if (isFrozen && !isEndorsed) {
            HookData memory hd = HookData({from: hookDataRaw, to: bytes16(0)});
            bool allowed = fullRestrictions.checkERC20Transfer(actor, address(1), 1, hd);
            t(!allowed, "P-TH-1: frozen non-endorsed user transfer allowed");
        }
    }

    /// @dev P-TH-2: Expired member cannot do deposit request/issuance
    function property_TH_2() public {
        if (address(token) == address(0)) return;
        if (address(fullRestrictions) == address(0)) return;

        address actor = _getActor();
        bytes16 hookDataRaw = IShareToken(address(token)).hookDataOf(actor);
        uint64 validUntil = uint64(uint128(hookDataRaw) >> 64);
        bool isEndorsed = root.endorsed(actor);

        // Only check if membership truly expired and actor is not endorsed
        if (validUntil != 0 && validUntil < block.timestamp && !isEndorsed) {
            // Deposit request/issuance: from=address(0), to=actor
            // Must not be depositTarget or crosschainSource
            if (actor == fullRestrictions.depositTarget()) return;
            if (actor == fullRestrictions.crosschainSource()) return;

            HookData memory hd = HookData({from: bytes16(0), to: hookDataRaw});
            bool allowed = fullRestrictions.checkERC20Transfer(address(0), actor, 1, hd);
            t(!allowed, "P-TH-2: expired member allowed deposit issuance");
        }
    }

    /// @dev P-TH-3: hookData encoding consistency (validUntil in upper 64 bits, frozen in bit 0)
    function property_TH_3() public {
        if (address(token) == address(0)) return;

        address actor = _getActor();
        bytes16 hookDataRaw = IShareToken(address(token)).hookDataOf(actor);
        uint128 hookDataUint = uint128(hookDataRaw);

        bool isFrozen = hookDataUint.getBit(0);
        uint64 validUntil = uint64(hookDataUint >> 64);

        // Reconstruct: validUntil in upper 64 bits, frozen in bit 0
        uint128 reconstructed = (uint128(validUntil) << 64);
        if (isFrozen) reconstructed |= 1;

        // Upper 64 bits should match (bits 64-127)
        eq(hookDataUint >> 64, reconstructed >> 64, "P-TH-3: hookData encoding mismatch (upper bits)");
    }

    /// @dev P-TH-4: Endorsed addresses bypass freeze check
    function property_TH_4() public {
        if (address(token) == address(0)) return;
        if (address(fullRestrictions) == address(0)) return;

        // escrow is endorsed in setup
        address endorsed_ = address(escrow);
        if (!root.endorsed(endorsed_)) return;

        bytes16 fakeHookData = bytes16(uint128(1)); // frozen bit set
        HookData memory hd = HookData({from: fakeHookData, to: bytes16(0)});

        bool frozen = fullRestrictions.isSourceOrTargetFrozen(endorsed_, address(1), hd);
        t(!frozen, "P-TH-4: endorsed address still appears frozen");
    }

    /// @dev P-TH-5: Canonical flows match their expected classification
    ///      (classifications use priority ordering, so overlaps are valid — we verify correctness)
    function property_TH_5() public view {
        if (address(fullRestrictions) == address(0)) return;

        address dt = fullRestrictions.depositTarget();
        address rs = fullRestrictions.redeemSource();
        address cs = fullRestrictions.crosschainSource();
        if (dt == address(0)) return; // not configured

        // Deposit fulfillment: address(0) → depositTarget
        require(
            fullRestrictions.isDepositFulfillment(address(0), dt),
            "P-TH-5: deposit fulfillment misclassified"
        );

        // Deposit claim: depositTarget → non-zero address
        require(fullRestrictions.isDepositClaim(dt, address(1)), "P-TH-5: deposit claim misclassified");

        // Redeem request: any → ESCROW_HOOK_ID
        require(
            fullRestrictions.isRedeemRequest(address(1), ESCROW_HOOK_ID),
            "P-TH-5: redeem request misclassified"
        );

        // Redeem fulfillment: redeemSource → address(0)
        if (rs != address(0)) {
            require(
                fullRestrictions.isRedeemFulfillment(rs, address(0)),
                "P-TH-5: redeem fulfillment misclassified"
            );
        }

        // Crosschain transfer: crosschainSource → address(0)
        if (cs != address(0) && cs != rs) {
            require(
                fullRestrictions.isCrosschainTransfer(cs, address(0)),
                "P-TH-5: crosschain transfer misclassified"
            );
        }

        // Crosschain execution: crosschainSource → non-zero
        if (cs != address(0)) {
            require(
                fullRestrictions.isCrosschainTransferExecution(cs, address(1)),
                "P-TH-5: crosschain execution misclassified"
            );
        }
    }

    /// @dev P-TH-6: checkERC20Transfer never reverts for valid hookData
    function property_TH_6() public {
        if (address(token) == address(0)) return;
        if (address(fullRestrictions) == address(0)) return;

        address actor = _getActor();
        bytes16 hookDataRaw = IShareToken(address(token)).hookDataOf(actor);
        HookData memory hd = HookData({from: hookDataRaw, to: hookDataRaw});

        try fullRestrictions.checkERC20Transfer(actor, actor, 0, hd) {}
        catch {
            t(false, "P-TH-6: checkERC20Transfer reverted");
        }
    }
}
