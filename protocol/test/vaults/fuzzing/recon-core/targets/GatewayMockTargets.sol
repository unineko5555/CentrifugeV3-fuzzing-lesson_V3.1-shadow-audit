// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {vm} from "@chimera/Hevm.sol";

import {AsyncVault} from "src/vaults/AsyncVault.sol";
import {ShareToken} from "src/core/spoke/ShareToken.sol";
import {FullRestrictions} from "src/hooks/FullRestrictions.sol";
import {IBaseVault} from "src/vaults/interfaces/IBaseVault.sol";
import {IVault} from "src/core/spoke/interfaces/IVault.sol";
import {IVaultFactory} from "src/core/spoke/factories/interfaces/IVaultFactory.sol";
import {IRequestManager} from "src/core/interfaces/IRequestManager.sol";
import {PoolId} from "src/core/types/PoolId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {D18} from "src/misc/types/D18.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";
import {UpdateRestrictionMessageLib} from "src/hooks/libraries/UpdateRestrictionMessageLib.sol";
import {RequestCallbackMessageLib} from "src/vaults/libraries/RequestCallbackMessageLib.sol";
import {MockERC20} from "@recon/MockERC20.sol";

import {Properties} from "../properties/Properties.sol";
import {OpType} from "../BeforeAfter.sol";

/// @dev Mocked Gateway targets — pool/vault deployment and admin operations
abstract contract GatewayMockTargets is BaseTargetFunctions, Properties {
    using CastLib for *;

    bool hasDoneADeploy;

    /// @dev Full deployment: asset → pool → shareClass → requestManager → vault → link
    function deployNewTokenPoolAndShare(uint8 decimals, uint256 initialMintPerUsers)
        public
        notGovFuzzing
        returns (address newToken, address newShareToken, address newVault, uint128 newAssetId, bytes16 _scId)
    {
        require(!hasDoneADeploy);
        if (RECON_USE_SINGLE_DEPLOY) {
            hasDoneADeploy = true;
        }

        if (RECON_USE_HARDCODED_DECIMALS) {
            decimals = 18;
        }
        initialMintPerUsers = 1_000_000e18;
        decimals = decimals % RECON_MODULO_DECIMALS;

        // 1. Deploy and register asset
        newToken = _newAsset(decimals);
        ASSET_ID_COUNTER += 1;
        newAssetId = spoke_registerAsset(address(newToken), 0);

        // 2. Add pool (creates PoolEscrow via factory)
        LOCAL_POOL_COUNTER += 1;
        POOL_ID = (uint64(DEFAULT_DESTINATION_CHAIN) << 48) | uint64(LOCAL_POOL_COUNTER);
        spoke_addPool(POOL_ID);

        // 3. Add share class
        {
            string memory name = "Share";
            string memory symbol = "T1";
            (newShareToken,) = spoke_addShareClass(POOL_ID, SHARE_ID, name, symbol, 18, address(fullRestrictions));
        }

        // 4. Set request manager on spoke
        spoke.setRequestManager(PoolId.wrap(POOL_ID), IRequestManager(address(asyncRequestManager)));

        // 5. Set balanceSheet managers for this pool
        balanceSheet.updateManager(PoolId.wrap(POOL_ID), address(asyncRequestManager), true);
        balanceSheet.updateManager(PoolId.wrap(POOL_ID), address(syncManager), true);
        balanceSheet.updateManager(PoolId.wrap(POOL_ID), address(this), true); // test contract is manager for fulfillment

        // 6. Deploy and link vault via VaultRegistry
        newVault = _deployAndLinkVault(POOL_ID, SHARE_ID, newAssetId);

        // 7. Finalize: approve and mint to actors
        address[] memory approvals = new address[](2);
        approvals[0] = address(spoke);
        approvals[1] = address(newVault);
        _finalizeAssetDeployment(_getActors(), approvals, initialMintPerUsers);

        // 8. Set active references
        vault = AsyncVault(newVault);
        token = ShareToken(newShareToken);
        fullRestrictions = FullRestrictions(address(token.hook()));

        _scId = SHARE_ID;
        poolId = POOL_ID;
        assetId = newAssetId;
    }

    // === Individual Steps === //

    function spoke_registerAsset(address assetAddress, uint256 erc6909TokenId)
        public
        notGovFuzzing
        asAdmin
        returns (uint128 _assetId)
    {
        _assetId = spoke.registerAsset{value: 0.1 ether}(DEFAULT_DESTINATION_CHAIN, assetAddress, erc6909TokenId, address(this)).raw();
        assetAddressToAssetId[assetAddress] = _assetId;
        assetIdToAssetAddress[_assetId] = assetAddress;
    }

    function spoke_addPool(uint64 _poolId) public notGovFuzzing asAdmin {
        spoke.addPool(PoolId.wrap(_poolId));
    }

    function spoke_addShareClass(
        uint64 _poolId,
        bytes16 _scId,
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimals,
        address hook
    ) public notGovFuzzing asAdmin returns (address, bytes16) {
        spoke.addShareClass(
            PoolId.wrap(_poolId),
            ShareClassId.wrap(_scId),
            tokenName,
            tokenSymbol,
            decimals,
            keccak256(abi.encodePacked(_poolId, _scId)),
            hook
        );

        address newToken = address(spoke.shareToken(PoolId.wrap(_poolId), ShareClassId.wrap(_scId)));
        shareClassTokens.push(newToken);
        return (newToken, _scId);
    }

    function _deployAndLinkVault(uint64 _poolId, bytes16 _scId, uint128 _assetId)
        internal
        returns (address)
    {
        IVault newVault =
            vaultRegistry.deployVault(PoolId.wrap(_poolId), ShareClassId.wrap(_scId), AssetId.wrap(_assetId), IVaultFactory(address(vaultFactory)));
        vaultRegistry.linkVault(
            PoolId.wrap(_poolId), ShareClassId.wrap(_scId), AssetId.wrap(_assetId), newVault
        );

        vaults.push(address(newVault));
        return address(newVault);
    }

    function removeVault_clamped() public asAdmin {
        vaultRegistry.unlinkVault(
            PoolId.wrap(poolId),
            ShareClassId.wrap(scId),
            AssetId.wrap(assetId),
            IVault(vaults[0])
        );
    }

    // === Admin Operations === //

    function spoke_updateMember(uint64 validUntil) public asAdmin {
        spoke.updateRestriction(
            PoolId.wrap(poolId),
            ShareClassId.wrap(scId),
            UpdateRestrictionMessageLib.serialize(
                UpdateRestrictionMessageLib.UpdateRestrictionMember(_getActor().toBytes32(), validUntil)
            )
        );
    }

    function spoke_updatePricePoolPerShare(uint64 price, uint64 computedAt)
        public
        updateGhostsWithType(OpType.ADMIN)
        asAdmin
    {
        spoke.updatePricePoolPerShare(PoolId.wrap(poolId), ShareClassId.wrap(scId), D18.wrap(price), computedAt);
        spoke.updatePricePoolPerAsset(
            PoolId.wrap(poolId), ShareClassId.wrap(scId), AssetId.wrap(assetId), D18.wrap(price), computedAt
        );
    }

    function spoke_updateShareMetadata(string memory tokenName, string memory tokenSymbol) public asAdmin {
        spoke.updateShareMetadata(PoolId.wrap(poolId), ShareClassId.wrap(scId), tokenName, tokenSymbol);
    }

    function spoke_freeze() public asAdmin {
        spoke.updateRestriction(
            PoolId.wrap(poolId),
            ShareClassId.wrap(scId),
            UpdateRestrictionMessageLib.serialize(
                UpdateRestrictionMessageLib.UpdateRestrictionFreeze(_getActor().toBytes32())
            )
        );
    }

    function spoke_unfreeze() public asAdmin {
        spoke.updateRestriction(
            PoolId.wrap(poolId),
            ShareClassId.wrap(scId),
            UpdateRestrictionMessageLib.serialize(
                UpdateRestrictionMessageLib.UpdateRestrictionUnfreeze(_getActor().toBytes32())
            )
        );
    }

    function root_scheduleRely(address target) public asAdmin {
        root.scheduleRely(target);
    }

    function root_cancelRely(address target) public asAdmin {
        root.cancelRely(target);
    }

    // === Spoke requestCallback dispatch targets === //

    /// @dev Full dispatch chain: Spoke.requestCallback → ARM.callback → approvedDeposits
    function spoke_requestCallback_approvedDeposits(uint128 assetAmount, uint128 price)
        public
        notGovFuzzing
        updateGhostsWithType(OpType.ADMIN)
    {
        (address asset,) = spoke.idToAsset(AssetId.wrap(assetId));
        uint256 available = MockERC20(asset).balanceOf(address(escrow));
        if (available == 0) return;
        assetAmount = uint128(uint256(assetAmount) % available);
        if (assetAmount == 0) assetAmount = 1;
        price = uint128(uint256(price) % 1000e18) + 1e15;

        bytes memory payload = RequestCallbackMessageLib.serialize(
            RequestCallbackMessageLib.ApprovedDeposits({assetAmount: assetAmount, pricePoolPerAsset: price})
        );
        try spoke.requestCallback(PoolId.wrap(poolId), ShareClassId.wrap(scId), AssetId.wrap(assetId), payload) {
            sumOfTransfersOut[asset] += assetAmount;
            mintedByCurrencyPayout[asset] += assetAmount;
        } catch {}
    }

    /// @dev Full dispatch chain: Spoke.requestCallback → ARM.callback → issuedShares
    function spoke_requestCallback_issuedShares(uint128 shareAmount, uint128 price)
        public
        notGovFuzzing
        updateGhostsWithType(OpType.ADMIN)
    {
        shareAmount = uint128(uint256(shareAmount) % 1_000_000e18) + 1;
        price = uint128(uint256(price) % 1000e18) + 1e15;

        bytes memory payload = RequestCallbackMessageLib.serialize(
            RequestCallbackMessageLib.IssuedShares({shareAmount: shareAmount, pricePoolPerShare: price})
        );
        try spoke.requestCallback(PoolId.wrap(poolId), ShareClassId.wrap(scId), AssetId.wrap(assetId), payload) {
            sumOfFullfilledDeposits[address(token)] += shareAmount;
            shareMints[address(token)] += shareAmount;
        } catch {}
    }

    // === Spoke Admin Targets (coverage improvement) === //

    /// @dev Set max age for share price staleness check
    function spoke_setMaxSharePriceAge(uint64 maxPriceAge) public asAdmin {
        spoke.setMaxSharePriceAge(PoolId.wrap(poolId), ShareClassId.wrap(scId), maxPriceAge);
    }

    /// @dev Set max age for asset price staleness check
    function spoke_setMaxAssetPriceAge(uint64 maxPriceAge) public asAdmin {
        spoke.setMaxAssetPriceAge(PoolId.wrap(poolId), ShareClassId.wrap(scId), AssetId.wrap(assetId), maxPriceAge);
    }

    /// @dev Hub→Spoke: execute cross-chain share transfer (mint + transfer to receiver)
    function spoke_executeTransferShares(uint128 amount, uint256 receiverEntropy)
        public
        updateGhostsWithType(OpType.ADMIN)
        asAdmin
    {
        address receiver = _getRandomActor(receiverEntropy);
        try spoke.executeTransferShares(
            PoolId.wrap(poolId), ShareClassId.wrap(scId), receiver.toBytes32(), amount
        ) {
            shareMints[address(token)] += amount;
        } catch {}
    }

    /// @dev Hub→Spoke: toggle share token hook between FullRestrictions and FreelyTransferable
    function spoke_updateShareHook() public asAdmin {
        address currentHook = address(token.hook());
        address newHook = currentHook == address(fullRestrictions) ? address(altHook) : address(fullRestrictions);
        try spoke.updateShareHook(PoolId.wrap(poolId), ShareClassId.wrap(scId), newHook) {} catch {}
    }

    /// @dev Public: send untrusted contract update to Hub
    function spoke_updateContract(bytes32 target, bytes memory payload) public {
        try spoke.updateContract(PoolId.wrap(poolId), ShareClassId.wrap(scId), target, payload, 0, msg.sender) {}
        catch {}
    }

    /// @dev Set extreme price (full uint64 range) to stress mulDiv rounding
    function spoke_updatePriceExtreme(uint64 price, uint64 computedAt)
        public
        updateGhostsWithType(OpType.ADMIN)
        asAdmin
    {
        if (price == 0) price = 1;
        spoke.updatePricePoolPerShare(PoolId.wrap(poolId), ShareClassId.wrap(scId), D18.wrap(price), computedAt);
        spoke.updatePricePoolPerAsset(
            PoolId.wrap(poolId), ShareClassId.wrap(scId), AssetId.wrap(assetId), D18.wrap(price), computedAt
        );
    }
}
