// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Asserts} from "@chimera/Asserts.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {AccountId} from "src/core/types/AccountId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";

import {D18} from "src/misc/types/D18.sol";

import {BeforeAfter} from "../BeforeAfter.sol";

/// @title HubAccountingProperties
/// @notice Hub-side accounting invariants adapted for E2E context.
///         Verifies double-entry bookkeeping, holdings consistency, and account soundness.
abstract contract HubAccountingProperties is BeforeAfter, Asserts {
    // ===================================================================
    // P-ACC-1: Holdings Value == Account Value (Asset Account)
    // ===================================================================

    /// @dev The holding's value should match the asset account's value
    function property_ACC_1_holdings_account_consistency() public {
        if (createdPools.length == 0) return;

        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId pid = createdPools[i];
            AssetId aid = poolCurrency[pid];
            ShareClassId[] storage scs = poolShareClasses[pid];

            for (uint256 j = 0; j < scs.length; j++) {
                (, uint128 holdingValue,,) = holdings.holding(pid, scs[j], aid);

                AccountId assetAccId = holdings.accountId(pid, scs[j], aid, 0);
                (,,, uint64 lastUpdated,) = accounting.accounts(pid, assetAccId);
                if (lastUpdated == 0) continue;

                (, uint128 accountVal) = accounting.accountValue(pid, assetAccId);

                eq(
                    uint256(holdingValue),
                    uint256(accountVal),
                    "P-ACC-1: holding value != asset account value"
                );
            }
        }
    }

    // ===================================================================
    // P-ACC-2: Account Debit/Credit <= int128.max
    // ===================================================================

    /// @dev Account totalDebit and totalCredit must not exceed int128.max
    function property_ACC_2_debit_credit_bounds() public {
        if (createdPools.length == 0) return;

        uint128 maxInt128 = uint128(type(int128).max);

        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId pid = createdPools[i];
            AssetId aid = poolCurrency[pid];
            ShareClassId[] storage scs = poolShareClasses[pid];

            for (uint256 j = 0; j < scs.length; j++) {
                for (uint8 kind = 0; kind < 6; kind++) {
                    AccountId accId = holdings.accountId(pid, scs[j], aid, kind);
                    (uint128 totalDebit, uint128 totalCredit,,,) = accounting.accounts(pid, accId);

                    lte(uint256(totalDebit), uint256(maxInt128), "P-ACC-2a: totalDebit > int128.max");
                    lte(uint256(totalCredit), uint256(maxInt128), "P-ACC-2b: totalCredit > int128.max");
                }
            }
        }
    }

    // ===================================================================
    // P-ACC-3: Asset Soundness (asset == equity + gain - loss)
    // ===================================================================

    /// @dev Fundamental accounting equation with 1 wei tolerance
    function property_ACC_3_asset_soundness() public {
        if (createdPools.length == 0) return;

        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId pid = createdPools[i];
            AssetId aid = poolCurrency[pid];
            ShareClassId[] storage scs = poolShareClasses[pid];

            for (uint256 j = 0; j < scs.length; j++) {
                AccountId assetAccId = holdings.accountId(pid, scs[j], aid, 0);
                AccountId equityAccId = holdings.accountId(pid, scs[j], aid, 1);
                AccountId gainAccId = holdings.accountId(pid, scs[j], aid, 2);
                AccountId lossAccId = holdings.accountId(pid, scs[j], aid, 3);

                (,,, uint64 lastUpdated,) = accounting.accounts(pid, assetAccId);
                if (lastUpdated == 0) continue;

                (, uint128 assetVal) = accounting.accountValue(pid, assetAccId);
                (, uint128 equityVal) = accounting.accountValue(pid, equityAccId);
                (, uint128 gainVal) = accounting.accountValue(pid, gainAccId);
                (, uint128 lossVal) = accounting.accountValue(pid, lossAccId);

                // asset + loss = equity + gain
                uint256 lhs = uint256(assetVal) + uint256(lossVal);
                uint256 rhs = uint256(equityVal) + uint256(gainVal);
                uint256 diff = lhs > rhs ? lhs - rhs : rhs - lhs;

                lte(diff, 1, "P-ACC-3: asset + loss != equity + gain (>1 wei)");
            }
        }
    }

    // ===================================================================
    // P-ACC-4: Identity Valuation Returns 1e18
    // ===================================================================

    /// @dev IdentityValuation always returns d18(1e18)
    function property_ACC_4_identity_valuation() public view {
        if (createdPools.length == 0) return;

        PoolId pid = createdPools[0];
        AssetId aid = poolCurrency[pid];
        ShareClassId[] storage scs = poolShareClasses[pid];

        if (scs.length > 0) {
            try identityValuation.getPrice(pid, scs[0], aid) returns (D18 val) {
                assert(D18.unwrap(val) == 1e18);
            } catch {}
        }
    }
}
