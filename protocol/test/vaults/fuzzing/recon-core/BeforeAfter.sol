// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {vm} from "@chimera/Hevm.sol";
import {MockERC20} from "@recon/MockERC20.sol";

import {AsyncInvestmentState} from "src/vaults/interfaces/IVaultManagers.sol";
import {IBaseVault} from "src/vaults/interfaces/IBaseVault.sol";
import {PoolId} from "src/core/types/PoolId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {D18} from "src/misc/types/D18.sol";

import {Ghosts} from "./helpers/Ghosts.sol";

enum OpType {
    GENERIC,
    ADMIN
}

abstract contract BeforeAfter is Ghosts {
    struct BeforeAfterVars {
        mapping(address investor => AsyncInvestmentState) investments;
        uint256 escrowTokenBalance;
        uint256 escrowTrancheTokenBalance;
        uint256 totalAssets;
        uint256 actualAssets;
        uint256 pricePerShare;
        uint256 totalShareSupply;
    }

    BeforeAfterVars internal _before;
    BeforeAfterVars internal _after;
    OpType internal currentOperation;

    modifier updateGhosts() {
        currentOperation = OpType.GENERIC;
        __before();
        _;
        __after();
    }

    modifier updateGhostsWithType(OpType op) {
        currentOperation = op;
        __before();
        _;
        __after();
    }

    function __before() internal {
        address[] memory actors = _getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            (
                uint128 maxMint,
                uint128 maxWithdraw,
                D18 depositPrice,
                D18 redeemPrice,
                uint128 pendingDepositRequest,
                uint128 pendingRedeemRequest,
                uint128 claimableCancelDepositRequest,
                uint128 claimableCancelRedeemRequest,
                bool pendingCancelDepositRequest,
                bool pendingCancelRedeemRequest
            ) = asyncRequestManager.investments(IBaseVault(address(vault)), actors[i]);
            _before.investments[actors[i]] = AsyncInvestmentState(
                maxMint,
                maxWithdraw,
                depositPrice,
                redeemPrice,
                pendingDepositRequest,
                pendingRedeemRequest,
                claimableCancelDepositRequest,
                claimableCancelRedeemRequest,
                pendingCancelDepositRequest,
                pendingCancelRedeemRequest
            );
        }
        _before.escrowTokenBalance = MockERC20(vault.asset()).balanceOf(address(escrow));
        _before.escrowTrancheTokenBalance = token.balanceOf(address(escrow));
        _before.actualAssets = MockERC20(vault.asset()).balanceOf(address(vault));
        _before.totalShareSupply = token.totalSupply();

        if (_priceAssetNonZero()) {
            _before.totalAssets = vault.totalAssets();
        } else {
            _before.totalAssets = 0;
        }

        if (_priceShareNonZero()) {
            _before.pricePerShare = vault.pricePerShare();
        } else {
            _before.pricePerShare = 0;
        }
    }

    function __after() internal {
        address[] memory actors = _getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            (
                uint128 maxMint,
                uint128 maxWithdraw,
                D18 depositPrice,
                D18 redeemPrice,
                uint128 pendingDepositRequest,
                uint128 pendingRedeemRequest,
                uint128 claimableCancelDepositRequest,
                uint128 claimableCancelRedeemRequest,
                bool pendingCancelDepositRequest,
                bool pendingCancelRedeemRequest
            ) = asyncRequestManager.investments(IBaseVault(address(vault)), actors[i]);
            _after.investments[actors[i]] = AsyncInvestmentState(
                maxMint,
                maxWithdraw,
                depositPrice,
                redeemPrice,
                pendingDepositRequest,
                pendingRedeemRequest,
                claimableCancelDepositRequest,
                claimableCancelRedeemRequest,
                pendingCancelDepositRequest,
                pendingCancelRedeemRequest
            );
        }
        _after.escrowTokenBalance = MockERC20(vault.asset()).balanceOf(address(escrow));
        _after.escrowTrancheTokenBalance = token.balanceOf(address(escrow));
        _after.actualAssets = MockERC20(vault.asset()).balanceOf(address(vault));
        _after.totalShareSupply = token.totalSupply();

        if (_priceAssetNonZero()) {
            _after.totalAssets = vault.totalAssets();
        } else {
            _after.totalAssets = 0;
        }

        if (_priceShareNonZero()) {
            _after.pricePerShare = vault.pricePerShare();
        } else {
            _after.pricePerShare = 0;
        }
    }

    function _priceAssetNonZero() internal view returns (bool) {
        (D18 priceAsset) =
            spoke.pricePoolPerAsset(PoolId.wrap(poolId), ShareClassId.wrap(scId), AssetId.wrap(assetId), false);
        return priceAsset.raw() != 0;
    }

    function _priceShareNonZero() internal view returns (bool) {
        (D18 priceShare) = spoke.pricePoolPerShare(PoolId.wrap(poolId), ShareClassId.wrap(scId), false);
        return priceShare.raw() != 0;
    }
}
