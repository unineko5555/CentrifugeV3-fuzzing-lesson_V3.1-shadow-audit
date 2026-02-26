// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseSetup} from "@chimera/BaseSetup.sol";
import {vm} from "@chimera/Hevm.sol";
import {ActorManager} from "@recon/ActorManager.sol";
import {AssetManager} from "@recon/AssetManager.sol";
import {MockERC20} from "@recon/MockERC20.sol";

// Core contracts
import {Root} from "src/admin/Root.sol";
import {IRoot} from "src/admin/interfaces/IRoot.sol";
import {Escrow} from "src/misc/Escrow.sol";
import {Spoke} from "src/core/spoke/Spoke.sol";
import {BalanceSheet} from "src/core/spoke/BalanceSheet.sol";
import {VaultRegistry} from "src/core/spoke/VaultRegistry.sol";
import {ShareToken} from "src/core/spoke/ShareToken.sol";

// Vault contracts
import {AsyncRequestManager} from "src/vaults/AsyncRequestManager.sol";
import {SyncManager} from "src/vaults/SyncManager.sol";
import {AsyncVault} from "src/vaults/AsyncVault.sol";

// Factories
import {AsyncVaultFactory} from "src/vaults/factories/AsyncVaultFactory.sol";
import {RefundEscrowFactory} from "src/vaults/factories/RefundEscrowFactory.sol";
import {TokenFactory} from "src/core/spoke/factories/TokenFactory.sol";
import {PoolEscrowFactory} from "src/core/spoke/factories/PoolEscrowFactory.sol";

// Hooks
import {FullRestrictions} from "src/hooks/FullRestrictions.sol";

// Types
import {IEscrow} from "src/misc/interfaces/IEscrow.sol";
import {IEndorsements} from "src/admin/interfaces/IRoot.sol";
import {IRefundEscrowFactory} from "src/vaults/factories/interfaces/IRefundEscrowFactory.sol";
import {ITokenFactory} from "src/core/spoke/factories/interfaces/ITokenFactory.sol";
import {IVaultFactory} from "src/core/spoke/factories/interfaces/IVaultFactory.sol";
import {IRequestManager} from "src/core/interfaces/IRequestManager.sol";
import {IBaseVault} from "src/vaults/interfaces/IBaseVault.sol";
import {PoolId} from "src/core/types/PoolId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AssetId} from "src/core/types/AssetId.sol";
import {D18} from "src/misc/types/D18.sol";

// Mocks
import {MockGateway} from "./mocks/MockGateway.sol";
import {MockHub} from "./mocks/MockHub.sol";
import {MockMessageSender} from "./mocks/MockMessageSender.sol";

// Helpers
import {SharedStorage} from "./helpers/SharedStorage.sol";

abstract contract Setup is BaseSetup, SharedStorage, ActorManager, AssetManager {
    // Core
    Root public root;
    Escrow public escrow;
    Spoke public spoke;
    BalanceSheet public balanceSheet;
    VaultRegistry public vaultRegistry;

    // Vault managers
    AsyncRequestManager public asyncRequestManager;
    SyncManager public syncManager;

    // Factories
    AsyncVaultFactory public vaultFactory;
    TokenFactory public tokenFactory;
    PoolEscrowFactory public poolEscrowFactory;
    RefundEscrowFactory public refundEscrowFactory;

    // Hooks
    FullRestrictions public fullRestrictions;

    // Active vault/token (set by deployNewTokenPoolAndShare)
    AsyncVault public vault;
    ShareToken public token;

    // Mocks
    MockGateway public gateway;
    MockHub public hub;
    MockMessageSender public messageSender;

    // Pool-specific IDs
    bytes16 scId;
    uint64 poolId;
    uint128 assetId;

    // Fork testing support
    uint256 totalSupplyAtFork;
    uint256 tokenBalanceOfEscrowAtFork;
    uint256 trancheTokenBalanceOfEscrowAtFork;
    bool forked;

    // Constants
    uint16 CENTRIFUGE_CHAIN_ID = 1;
    uint256 REQUEST_ID = 0;

    // Gov fuzzing
    bool GOV_FUZZING = false;

    modifier asAdmin() {
        vm.prank(address(this));
        _;
    }

    modifier asActor() {
        vm.prank(address(_getActor()));
        _;
    }

    modifier tokenIsSet() {
        require(address(token) != address(0));
        _;
    }

    modifier assetIsSet() {
        require(_getAsset() != address(0));
        _;
    }

    modifier notGovFuzzing() {
        require(!GOV_FUZZING);
        _;
    }

    // Accept any call (for root.rely callbacks, etc.)
    fallback() external payable {}
    receive() external payable {}

    function setup() internal virtual override {
        // 1. Deploy Root with delay=0 for testing
        root = new Root(0, address(this));

        // 2. Deploy global Escrow
        escrow = new Escrow(address(this));

        // 3. Deploy mocks
        gateway = new MockGateway();
        messageSender = new MockMessageSender(CENTRIFUGE_CHAIN_ID);
        hub = new MockHub();

        // 4. Deploy factories
        tokenFactory = new TokenFactory(address(root), address(this));
        poolEscrowFactory = new PoolEscrowFactory(address(root), address(this));
        refundEscrowFactory = new RefundEscrowFactory(address(this));

        // 5. Deploy core spoke
        spoke = new Spoke(ITokenFactory(address(tokenFactory)), address(this));

        // 6. Deploy BalanceSheet
        //    BatchedMulticall(gateway) in constructor — gateway is zero-initialized, set via file() later
        balanceSheet = new BalanceSheet(IEndorsements(address(root)), address(this));

        // 7. Deploy VaultRegistry
        vaultRegistry = new VaultRegistry(address(this));

        // 8. Deploy AsyncRequestManager
        asyncRequestManager = new AsyncRequestManager(
            IEscrow(address(escrow)),
            IRefundEscrowFactory(address(refundEscrowFactory)),
            address(this)
        );

        // 9. Deploy SyncManager
        syncManager = new SyncManager(address(this));

        // 10. Deploy AsyncVaultFactory
        vaultFactory = new AsyncVaultFactory(address(root), asyncRequestManager, address(this));

        // 11. Deploy FullRestrictions
        //     redeemSource = balanceSheet, depositTarget = escrow, crosschainSource = spoke
        //     All three must be distinct ✓
        fullRestrictions = new FullRestrictions(
            address(root),
            address(spoke),
            address(balanceSheet), // redeemSource
            address(escrow), // depositTarget
            address(spoke) == address(escrow) ? address(this) : address(spoke), // crosschainSource — guaranteed distinct
            address(this)
        );

        // ===== file() wiring ===== //

        // Spoke dependencies
        spoke.file("gateway", address(gateway));
        spoke.file("sender", address(messageSender));
        spoke.file("poolEscrowFactory", address(poolEscrowFactory));

        // BalanceSheet dependencies
        balanceSheet.file("spoke", address(spoke));
        balanceSheet.file("sender", address(messageSender));
        balanceSheet.file("gateway", address(gateway));
        balanceSheet.file("poolEscrowProvider", address(poolEscrowFactory));

        // AsyncRequestManager dependencies
        asyncRequestManager.file("spoke", address(spoke));
        asyncRequestManager.file("vaultRegistry", address(vaultRegistry));
        asyncRequestManager.file("balanceSheet", address(balanceSheet));

        // SyncManager dependencies
        syncManager.file("spoke", address(spoke));
        syncManager.file("vaultRegistry", address(vaultRegistry));
        syncManager.file("balanceSheet", address(balanceSheet));

        // VaultRegistry dependencies
        vaultRegistry.file("spoke", address(spoke));

        // PoolEscrowFactory dependencies
        poolEscrowFactory.file("gateway", address(gateway));
        poolEscrowFactory.file("balanceSheet", address(balanceSheet));

        // RefundEscrowFactory dependencies
        refundEscrowFactory.file("controller", address(asyncRequestManager));
        refundEscrowFactory.file("root", address(root));

        // TokenFactory — set wards that token needs to rely on
        address[] memory tokenWards = new address[](2);
        tokenWards[0] = address(balanceSheet);
        tokenWards[1] = address(spoke);
        tokenFactory.file("wards", tokenWards);

        // ===== rely() wiring ===== //

        // AsyncRequestManager: spoke, vaultFactory can call it
        asyncRequestManager.rely(address(spoke));
        asyncRequestManager.rely(address(vaultFactory));

        // Spoke: gateway handler calls are auth-gated, vaultRegistry calls setShareTokenVault
        spoke.rely(address(gateway));
        spoke.rely(address(vaultRegistry));

        // BalanceSheet: request managers need access
        balanceSheet.rely(address(asyncRequestManager));
        balanceSheet.rely(address(syncManager));

        // Global Escrow: request manager, spoke, and balanceSheet need transfer auth
        escrow.rely(address(asyncRequestManager));
        escrow.rely(address(spoke));
        escrow.rely(address(balanceSheet));

        // FullRestrictions: spoke updates restrictions
        fullRestrictions.rely(address(spoke));

        // VaultRegistry: spoke is auth'd
        vaultRegistry.rely(address(spoke));

        // Factories
        vaultFactory.rely(address(vaultRegistry));
        tokenFactory.rely(address(spoke));
        poolEscrowFactory.rely(address(spoke));
        refundEscrowFactory.rely(address(asyncRequestManager));

        // Root endorsements (endorsed addresses bypass FullRestrictions transfer hooks)
        root.endorse(address(escrow));
        root.endorse(address(balanceSheet));
        root.endorse(address(spoke));
        root.endorse(address(asyncRequestManager));
    }

    /// @dev Returns a random actor from the list of actors
    function _getRandomActor(uint256 entropy) internal view returns (address randomActor) {
        address[] memory actorsArray = _getActors();
        randomActor = actorsArray[entropy % actorsArray.length];
    }
}
