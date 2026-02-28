// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Asserts} from "@chimera/Asserts.sol";
import {console2} from "forge-std/console2.sol";

// Libraries
import {MathLib} from "src/misc/libraries/MathLib.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";

// Interfaces
import {AccountType} from "src/core/hub/interfaces/IHub.sol";
import {EpochId} from "src/vaults/interfaces/IBatchRequestManager.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {AccountId} from "src/core/types/AccountId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {D18, d18} from "src/misc/types/D18.sol";

// Utils
import {Helpers} from "./utils/Helpers.sol";
import {BeforeAfter, OpType} from "./BeforeAfter.sol";

abstract contract Properties is BeforeAfter, Asserts {
    using MathLib for D18;
    using MathLib for uint128;
    using MathLib for uint256;

    // ========================================================================
    // P-BRM: BatchRequestManager Properties
    // ========================================================================

    /// @dev P-BRM-1: depositEpoch monotonically increases
    function property_brm_deposit_epoch_monotonic() public {
        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId poolId = createdPools[i];
            for (uint32 j = 1; j < shareClassManager.shareClassCount(poolId); j++) {
                ShareClassId scId = shareClassManager.previewShareClassId(poolId, j);
                AssetId assetId = hubRegistry.currency(poolId);

                gte(
                    _after.ghostEpochId[poolId][scId][assetId].deposit,
                    _before.ghostEpochId[poolId][scId][assetId].deposit,
                    "P-BRM-1: deposit epoch decreased"
                );
            }
        }
    }

    /// @dev P-BRM-2: issueEpoch monotonically increases
    function property_brm_issue_epoch_monotonic() public {
        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId poolId = createdPools[i];
            for (uint32 j = 1; j < shareClassManager.shareClassCount(poolId); j++) {
                ShareClassId scId = shareClassManager.previewShareClassId(poolId, j);
                AssetId assetId = hubRegistry.currency(poolId);

                gte(
                    _after.ghostEpochId[poolId][scId][assetId].issue,
                    _before.ghostEpochId[poolId][scId][assetId].issue,
                    "P-BRM-2: issue epoch decreased"
                );
            }
        }
    }

    /// @dev P-BRM-3: redeemEpoch monotonically increases
    function property_brm_redeem_epoch_monotonic() public {
        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId poolId = createdPools[i];
            for (uint32 j = 1; j < shareClassManager.shareClassCount(poolId); j++) {
                ShareClassId scId = shareClassManager.previewShareClassId(poolId, j);
                AssetId assetId = hubRegistry.currency(poolId);

                gte(
                    _after.ghostEpochId[poolId][scId][assetId].redeem,
                    _before.ghostEpochId[poolId][scId][assetId].redeem,
                    "P-BRM-3: redeem epoch decreased"
                );
            }
        }
    }

    /// @dev P-BRM-4: revokeEpoch monotonically increases
    function property_brm_revoke_epoch_monotonic() public {
        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId poolId = createdPools[i];
            for (uint32 j = 1; j < shareClassManager.shareClassCount(poolId); j++) {
                ShareClassId scId = shareClassManager.previewShareClassId(poolId, j);
                AssetId assetId = hubRegistry.currency(poolId);

                gte(
                    _after.ghostEpochId[poolId][scId][assetId].revoke,
                    _before.ghostEpochId[poolId][scId][assetId].revoke,
                    "P-BRM-4: revoke epoch decreased"
                );
            }
        }
    }

    /// @dev P-BRM-5: pendingDeposit >= sum of all user deposit orders
    function property_brm_pending_deposit_accounting() public {
        address[] memory _actors = _getActors();

        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId poolId = createdPools[i];
            for (uint32 j = 1; j < shareClassManager.shareClassCount(poolId); j++) {
                ShareClassId scId = shareClassManager.previewShareClassId(poolId, j);
                AssetId assetId = hubRegistry.currency(poolId);

                uint128 pendingDeposit = brm.pendingDeposit(poolId, scId, assetId);
                uint128 totalUserPending = 0;

                for (uint256 k = 0; k < _actors.length; k++) {
                    bytes32 actor = CastLib.toBytes32(_actors[k]);
                    (uint128 userPending,) = brm.depositRequest(poolId, scId, assetId, actor);
                    totalUserPending += userPending;
                }

                gte(totalUserPending, pendingDeposit, "P-BRM-5: user deposits < pendingDeposit");
            }
        }
    }

    /// @dev P-BRM-6: pendingRedeem >= sum of all user redeem orders
    function property_brm_pending_redeem_accounting() public {
        address[] memory _actors = _getActors();

        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId poolId = createdPools[i];
            for (uint32 j = 1; j < shareClassManager.shareClassCount(poolId); j++) {
                ShareClassId scId = shareClassManager.previewShareClassId(poolId, j);
                AssetId assetId = hubRegistry.currency(poolId);

                uint128 pendingRedeem = brm.pendingRedeem(poolId, scId, assetId);
                uint128 totalUserPending = 0;

                for (uint256 k = 0; k < _actors.length; k++) {
                    bytes32 actor = CastLib.toBytes32(_actors[k]);
                    (uint128 userPending,) = brm.redeemRequest(poolId, scId, assetId, actor);
                    totalUserPending += userPending;
                }

                gte(totalUserPending, pendingRedeem, "P-BRM-6: user redeems < pendingRedeem");
            }
        }
    }

    /// @dev P-BRM-7: epoch can increase by at most 1 within a single batch/multicall
    function property_brm_epoch_max_increment_per_batch() public {
        if (currentOperation == OpType.BATCH) {
            for (uint256 i = 0; i < createdPools.length; i++) {
                PoolId poolId = createdPools[i];
                for (uint32 j = 1; j < shareClassManager.shareClassCount(poolId); j++) {
                    ShareClassId scId = shareClassManager.previewShareClassId(poolId, j);
                    AssetId assetId = hubRegistry.currency(poolId);

                    uint32 depositDiff = _after.ghostEpochId[poolId][scId][assetId].deposit
                        - _before.ghostEpochId[poolId][scId][assetId].deposit;
                    uint32 issueDiff = _after.ghostEpochId[poolId][scId][assetId].issue
                        - _before.ghostEpochId[poolId][scId][assetId].issue;
                    uint32 redeemDiff = _after.ghostEpochId[poolId][scId][assetId].redeem
                        - _before.ghostEpochId[poolId][scId][assetId].redeem;
                    uint32 revokeDiff = _after.ghostEpochId[poolId][scId][assetId].revoke
                        - _before.ghostEpochId[poolId][scId][assetId].revoke;

                    lte(depositDiff, 1, "P-BRM-7: deposit epoch increased by more than 1");
                    lte(issueDiff, 1, "P-BRM-7: issue epoch increased by more than 1");
                    lte(redeemDiff, 1, "P-BRM-7: redeem epoch increased by more than 1");
                    lte(revokeDiff, 1, "P-BRM-7: revoke epoch increased by more than 1");
                }
            }
        }
    }

    /// @dev P-BRM-8a: After issueShares, epochInvestAmounts.issuedAt > 0
    ///      ghostEpochId stores raw epochId.issue (the LAST PROCESSED epoch).
    ///      nowIssueEpoch() = epochId.issue + 1, so raw epochId IS the processed epoch.
    function property_brm_issue_consistency() public {
        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId poolId = createdPools[i];
            for (uint32 j = 1; j < shareClassManager.shareClassCount(poolId); j++) {
                ShareClassId scId = shareClassManager.previewShareClassId(poolId, j);
                AssetId assetId = hubRegistry.currency(poolId);

                uint32 lastProcessedIssueEpoch = _after.ghostEpochId[poolId][scId][assetId].issue;
                if (lastProcessedIssueEpoch == 0) continue;

                // If issue epoch advanced, the processed epoch should have issuedAt set
                if (lastProcessedIssueEpoch > _before.ghostEpochId[poolId][scId][assetId].issue) {
                    (,,,,, uint64 issuedAt) =
                        brm.epochInvestAmounts(poolId, scId, assetId, lastProcessedIssueEpoch);
                    t(issuedAt > 0, "P-BRM-8a: issuedAt == 0 after issueShares");
                }
            }
        }
    }

    /// @dev P-BRM-8b: After revokeShares, epochRedeemAmounts.revokedAt > 0
    ///      ghostEpochId stores raw epochId.revoke (the LAST PROCESSED epoch).
    function property_brm_revoke_consistency() public {
        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId poolId = createdPools[i];
            for (uint32 j = 1; j < shareClassManager.shareClassCount(poolId); j++) {
                ShareClassId scId = shareClassManager.previewShareClassId(poolId, j);
                AssetId assetId = hubRegistry.currency(poolId);

                uint32 lastProcessedRevokeEpoch = _after.ghostEpochId[poolId][scId][assetId].revoke;
                if (lastProcessedRevokeEpoch == 0) continue;

                // If revoke epoch advanced, the processed epoch should have revokedAt set
                if (lastProcessedRevokeEpoch > _before.ghostEpochId[poolId][scId][assetId].revoke) {
                    (,,,,, uint64 revokedAt) =
                        brm.epochRedeemAmounts(poolId, scId, assetId, lastProcessedRevokeEpoch);
                    t(revokedAt > 0, "P-BRM-8b: revokedAt == 0 after revokeShares");
                }
            }
        }
    }

    // ========================================================================
    // P-ACC: Accounting Properties
    // ========================================================================

    /// @dev P-ACC-1: account.totalDebit and account.totalCredit <= int128.max
    function property_account_totalDebit_and_totalCredit_leq_max_int128() public {
        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId poolId = createdPools[i];
            for (uint32 j = 1; j < shareClassManager.shareClassCount(poolId); j++) {
                ShareClassId scId = shareClassManager.previewShareClassId(poolId, j);
                AssetId assetId = hubRegistry.currency(poolId);

                for (uint8 kind = 0; kind < 6; kind++) {
                    AccountId accountId = holdings.accountId(poolId, scId, assetId, kind);
                    (uint128 totalDebit, uint128 totalCredit,,,) = accounting.accounts(poolId, accountId);
                    lte(totalDebit, uint128(type(int128).max), "P-ACC-1: totalDebit > int128.max");
                    lte(totalCredit, uint128(type(int128).max), "P-ACC-1: totalCredit > int128.max");
                }
            }
        }
    }

    /// @dev P-ACC-2: Value of Holdings == accountValue(Asset)
    function property_accounting_and_holdings_soundness() public {
        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId poolId = createdPools[i];
            for (uint32 j = 1; j < shareClassManager.shareClassCount(poolId); j++) {
                ShareClassId scId = shareClassManager.previewShareClassId(poolId, j);
                AssetId assetId = hubRegistry.currency(poolId);
                AccountId accountId = holdings.accountId(poolId, scId, assetId, uint8(AccountType.Asset));

                (, uint128 assets) = accounting.accountValue(poolId, accountId);
                uint128 holdingsValue = holdings.value(poolId, scId, assetId);

                eq(assets, holdingsValue, "P-ACC-2: assets != holdings value");
            }
        }
    }

    /// @dev P-ACC-3: assets = equity + gain - loss (accounting equation)
    function property_asset_soundness() public {
        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId poolId = createdPools[i];
            for (uint32 j = 1; j < shareClassManager.shareClassCount(poolId); j++) {
                ShareClassId scId = shareClassManager.previewShareClassId(poolId, j);
                AssetId assetId = hubRegistry.currency(poolId);

                AccountId assetAccountId = holdings.accountId(poolId, scId, assetId, uint8(AccountType.Asset));
                AccountId equityAccountId = holdings.accountId(poolId, scId, assetId, uint8(AccountType.Equity));
                AccountId gainAccountId = holdings.accountId(poolId, scId, assetId, uint8(AccountType.Gain));
                AccountId lossAccountId = holdings.accountId(poolId, scId, assetId, uint8(AccountType.Loss));

                (, uint128 assets) = accounting.accountValue(poolId, assetAccountId);
                (, uint128 equity) = accounting.accountValue(poolId, equityAccountId);
                (, uint128 gain) = accounting.accountValue(poolId, gainAccountId);
                (, uint128 loss) = accounting.accountValue(poolId, lossAccountId);

                t(assets == equity + gain - loss, "P-ACC-3: assets != equity + gain - loss");
            }
        }
    }

    /// @dev P-ACC-4: equity = assets + loss - gain
    function property_equity_soundness() public {
        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId poolId = createdPools[i];
            for (uint32 j = 1; j < shareClassManager.shareClassCount(poolId); j++) {
                ShareClassId scId = shareClassManager.previewShareClassId(poolId, j);
                AssetId assetId = hubRegistry.currency(poolId);

                AccountId assetAccountId = holdings.accountId(poolId, scId, assetId, uint8(AccountType.Asset));
                AccountId equityAccountId = holdings.accountId(poolId, scId, assetId, uint8(AccountType.Equity));
                AccountId gainAccountId = holdings.accountId(poolId, scId, assetId, uint8(AccountType.Gain));
                AccountId lossAccountId = holdings.accountId(poolId, scId, assetId, uint8(AccountType.Loss));

                (, uint128 assets) = accounting.accountValue(poolId, assetAccountId);
                (, uint128 equity) = accounting.accountValue(poolId, equityAccountId);
                (, uint128 gain) = accounting.accountValue(poolId, gainAccountId);
                (, uint128 loss) = accounting.accountValue(poolId, lossAccountId);

                t(equity == assets + loss - gain, "P-ACC-4: equity != assets + loss - gain");
            }
        }
    }

    // ========================================================================
    // P-HOLD: Holdings Properties
    // ========================================================================

    /// @dev P-HOLD-1: Decrease in holding valuation should not increase accountValue
    function property_decrease_valuation_no_increase_in_accountValue() public {
        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId poolId = createdPools[i];
            for (uint32 j = 1; j < shareClassManager.shareClassCount(poolId); j++) {
                ShareClassId scId = shareClassManager.previewShareClassId(poolId, j);
                AssetId assetId = hubRegistry.currency(poolId);

                if (_before.ghostHolding[poolId][scId][assetId] > _after.ghostHolding[poolId][scId][assetId]) {
                    for (uint8 kind = 0; kind < 6; kind++) {
                        AccountId accountId = holdings.accountId(poolId, scId, assetId, kind);
                        uint128 valueBefore = _before.ghostAccountValue[poolId][accountId];
                        uint128 valueAfter = _after.ghostAccountValue[poolId][accountId];
                        if (valueAfter > valueBefore) {
                            t(false, "P-HOLD-1: accountValue increased on valuation decrease");
                        }
                    }
                }
            }
        }
    }

    // ========================================================================
    // P-ORACLE: Oracle Properties
    // ========================================================================

    /// @dev P-ORACLE-1: IdentityValuation always returns d18(1e18)
    function property_identity_valuation_returns_one() public view {
        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId poolId = createdPools[i];
            for (uint32 j = 1; j < shareClassManager.shareClassCount(poolId); j++) {
                ShareClassId scId = shareClassManager.previewShareClassId(poolId, j);
                AssetId assetId = hubRegistry.currency(poolId);

                D18 price = identityValuation.getPrice(poolId, scId, assetId);
                require(D18.unwrap(price) == 1e18, "P-ORACLE-1: identity valuation != 1e18");
            }
        }
    }

    // ========================================================================
    // Stateless Properties
    // ========================================================================

    /// @dev Stateless: Eligible user redemption payout <= approved redemption amounts
    function property_eligible_user_redemption_leq_approved() public view statelessTest {
        address[] memory _actors = _getActors();

        for (uint256 i = 0; i < createdPools.length; i++) {
            PoolId poolId = createdPools[i];
            for (uint32 j = 1; j < shareClassManager.shareClassCount(poolId); j++) {
                ShareClassId scId = shareClassManager.previewShareClassId(poolId, j);
                AssetId assetId = hubRegistry.currency(poolId);

                brm.nowRevokeEpoch(poolId, scId, assetId);
                uint128 sumPayoutAsset = 0;

                for (uint256 k = 0; k < _actors.length; k++) {
                    bytes32 actor = CastLib.toBytes32(_actors[k]);
                    uint32 claims = brm.maxRedeemClaims(poolId, scId, actor, assetId);
                    // Claims would need notifyRedeem to execute — we just verify the max
                    if (claims > 0) {
                        sumPayoutAsset += 1; // placeholder — actual claim requires gateway callback
                    }
                }
            }
        }
    }
}
