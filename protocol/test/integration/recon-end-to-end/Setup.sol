// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// ===================================================================
// Chimera / Recon
// ===================================================================
import {BaseSetup} from "@chimera/BaseSetup.sol";
import {vm} from "@chimera/Hevm.sol";
import {ActorManager} from "@recon/ActorManager.sol";
import {AssetManager} from "@recon/AssetManager.sol";
import {MockERC20} from "@recon/MockERC20.sol";

// ===================================================================
// Admin
// ===================================================================
import {Root} from "src/admin/Root.sol";
import {IRoot} from "src/admin/interfaces/IRoot.sol";
import {IEndorsements} from "src/admin/interfaces/IRoot.sol";

// ===================================================================
// Hub Core
// ===================================================================
import {Hub} from "src/core/hub/Hub.sol";
import {HubHandler} from "src/core/hub/HubHandler.sol";
import {Accounting} from "src/core/hub/Accounting.sol";
import {HubRegistry} from "src/core/hub/HubRegistry.sol";
import {Holdings} from "src/core/hub/Holdings.sol";
import {ShareClassManager} from "src/core/hub/ShareClassManager.sol";

import {IHub} from "src/core/hub/interfaces/IHub.sol";
import {IHoldings} from "src/core/hub/interfaces/IHoldings.sol";
import {IAccounting, JournalEntry} from "src/core/hub/interfaces/IAccounting.sol";
import {IHubRegistry} from "src/core/hub/interfaces/IHubRegistry.sol";
import {IShareClassManager} from "src/core/hub/interfaces/IShareClassManager.sol";

// ===================================================================
// Messaging
// ===================================================================
import {Gateway} from "src/core/messaging/Gateway.sol";
import {MultiAdapter, MAX_ADAPTER_COUNT} from "src/core/messaging/MultiAdapter.sol";
import {MessageProcessor} from "src/core/messaging/MessageProcessor.sol";
import {MessageDispatcher} from "src/core/messaging/MessageDispatcher.sol";
import {GasService} from "src/core/messaging/GasService.sol";

import {IGateway} from "src/core/messaging/interfaces/IGateway.sol";
import {IMultiAdapter} from "src/core/messaging/interfaces/IMultiAdapter.sol";
import {IAdapter} from "src/core/messaging/interfaces/IAdapter.sol";
import {IMessageHandler} from "src/core/messaging/interfaces/IMessageHandler.sol";
import {IProtocolPauser} from "src/core/messaging/interfaces/IProtocolPauser.sol";
import {IScheduleAuth} from "src/core/messaging/interfaces/IScheduleAuth.sol";

// ===================================================================
// Spoke Core
// ===================================================================
import {Spoke} from "src/core/spoke/Spoke.sol";
import {BalanceSheet} from "src/core/spoke/BalanceSheet.sol";
import {VaultRegistry} from "src/core/spoke/VaultRegistry.sol";
import {ShareToken} from "src/core/spoke/ShareToken.sol";

import {ISpoke} from "src/core/spoke/interfaces/ISpoke.sol";

// ===================================================================
// Spoke Factories
// ===================================================================
import {TokenFactory} from "src/core/spoke/factories/TokenFactory.sol";
import {PoolEscrowFactory} from "src/core/spoke/factories/PoolEscrowFactory.sol";
import {ITokenFactory} from "src/core/spoke/factories/interfaces/ITokenFactory.sol";

// ===================================================================
// Vault Contracts
// ===================================================================
import {BatchRequestManager} from "src/vaults/BatchRequestManager.sol";
import {AsyncRequestManager} from "src/vaults/AsyncRequestManager.sol";
import {SyncManager} from "src/vaults/SyncManager.sol";
import {AsyncVault} from "src/vaults/AsyncVault.sol";
import {AsyncVaultFactory} from "src/vaults/factories/AsyncVaultFactory.sol";
import {RefundEscrowFactory} from "src/vaults/factories/RefundEscrowFactory.sol";
import {IRefundEscrowFactory} from "src/vaults/factories/interfaces/IRefundEscrowFactory.sol";
import {IAsyncRequestManager} from "src/vaults/interfaces/IVaultManagers.sol";

// ===================================================================
// Managers
// ===================================================================
import {NAVManager} from "src/managers/hub/NAVManager.sol";
import {QueueManager} from "src/managers/spoke/QueueManager.sol";
import {IBalanceSheet} from "src/core/spoke/interfaces/IBalanceSheet.sol";

// ===================================================================
// Valuations
// ===================================================================
import {IdentityValuation} from "src/valuations/IdentityValuation.sol";
import {OracleValuation} from "src/valuations/OracleValuation.sol";

// ===================================================================
// Hooks
// ===================================================================
import {FullRestrictions} from "src/hooks/FullRestrictions.sol";

// ===================================================================
// Misc
// ===================================================================
import {Escrow} from "src/misc/Escrow.sol";
import {IEscrow} from "src/misc/interfaces/IEscrow.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId, newAssetId} from "src/core/types/AssetId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {AccountId} from "src/core/types/AccountId.sol";

// ===================================================================
// Local
// ===================================================================
import {SimplifiedLocalAdapter} from "./mocks/SimplifiedLocalAdapter.sol";
import {SharedStorage} from "./helpers/SharedStorage.sol";
import {Utils} from "./helpers/Utils.sol";

/// @title Setup
/// @notice Full Hub+Spoke E2E deployment for recon-e2e fuzzing.
///         Deploys ALL protocol contracts as REAL (not mocked), connected via SimplifiedLocalAdapter
///         for synchronous cross-chain message delivery.
///
/// Architecture:
///   Hub chain (centrifugeId=1): Gateway, MultiAdapter, MessageProcessor, MessageDispatcher,
///     GasService, Hub, HubHandler, Accounting, HubRegistry, Holdings, ShareClassManager,
///     BatchRequestManager, NAVManager, IdentityValuation
///   Spoke chain (centrifugeId=2): Gateway, MultiAdapter, MessageProcessor, MessageDispatcher,
///     GasService, Root, Escrow, Spoke, BalanceSheet, VaultRegistry, AsyncRequestManager,
///     SyncManager, TokenFactory, PoolEscrowFactory, AsyncVaultFactory, RefundEscrowFactory,
///     FullRestrictions
///   Bridge: SimplifiedLocalAdapter x2 (synchronous delivery)
abstract contract Setup is BaseSetup, SharedStorage, Utils, ActorManager, AssetManager {
    // ===================================================================
    // Admin (shared)
    // ===================================================================
    Root public root;
    Escrow public escrow;

    // ===================================================================
    // Hub Messaging
    // ===================================================================
    Gateway public hubGateway;
    MultiAdapter public hubMultiAdapter;
    MessageProcessor public hubMessageProcessor;
    MessageDispatcher public hubMessageDispatcher;
    GasService public hubGasService;

    // ===================================================================
    // Hub Core
    // ===================================================================
    Hub public hub;
    HubHandler public hubHandler;
    Accounting public accounting;
    HubRegistry public hubRegistry;
    Holdings public holdings;
    ShareClassManager public shareClassManager;

    // ===================================================================
    // Hub Vault + Managers
    // ===================================================================
    BatchRequestManager public brm;
    NAVManager public navManager;
    IdentityValuation public identityValuation;
    OracleValuation public oracleValuation;

    // ===================================================================
    // Spoke Messaging
    // ===================================================================
    Gateway public spokeGateway;
    MultiAdapter public spokeMultiAdapter;
    MessageProcessor public spokeMessageProcessor;
    MessageDispatcher public spokeMessageDispatcher;
    GasService public spokeGasService;

    // ===================================================================
    // Spoke Core
    // ===================================================================
    Spoke public spoke;
    BalanceSheet public balanceSheet;
    VaultRegistry public vaultRegistry;

    // ===================================================================
    // Spoke Vault + Managers
    // ===================================================================
    AsyncRequestManager public asyncRequestManager;
    SyncManager public syncManager;
    QueueManager public queueManager;
    AsyncVaultFactory public vaultFactory;
    RefundEscrowFactory public refundEscrowFactory;

    // ===================================================================
    // Spoke Factories
    // ===================================================================
    TokenFactory public tokenFactory;
    PoolEscrowFactory public poolEscrowFactory;

    // ===================================================================
    // Hooks
    // ===================================================================
    FullRestrictions public fullRestrictions;

    // ===================================================================
    // Bridge
    // ===================================================================
    SimplifiedLocalAdapter public adapterHubToSpoke;
    SimplifiedLocalAdapter public adapterSpokeToHub;

    // ===================================================================
    // Active vault/token (set by admin targets)
    // ===================================================================
    AsyncVault public vault;
    ShareToken public token;
    MockERC20 public defaultAsset;

    // ===================================================================
    // Active IDs (set by admin targets)
    // ===================================================================
    PoolId public activePoolId;
    ShareClassId public activeScId;
    AssetId public activeAssetId;

    // ===================================================================
    // Constants
    // ===================================================================
    D18 internal INITIAL_PRICE = d18(1e18);
    uint32 internal MAX_CLAIMS = 10;

    // ===================================================================
    // Modifiers
    // ===================================================================
    modifier asAdmin() {
        vm.prank(address(this));
        _;
    }

    modifier asActor() {
        vm.prank(address(_getActor()));
        _;
    }

    modifier poolExists() {
        require(createdPools.length > 0, "No pool created");
        _;
    }

    modifier vaultExists() {
        require(address(vault) != address(0), "No vault deployed");
        _;
    }

    // Accept any call (for root.rely callbacks, escrow transfers, etc.)
    fallback() external payable {}
    receive() external payable {}

    // ===================================================================
    // Setup
    // ===================================================================
    function setup() internal virtual override {
        // Add actors
        _addActor(address(0x10000));
        _addActor(address(0x20000));
        _addActor(address(0x30000));

        // -----------------------------------------------------------------
        // 1. Deploy Admin (shared)
        // -----------------------------------------------------------------
        root = new Root(0, address(this)); // delay=0 for testing
        escrow = new Escrow(address(this));

        // -----------------------------------------------------------------
        // 2. Deploy Hub Messaging Stack
        // -----------------------------------------------------------------
        // Root implements IProtocolPauser and IScheduleAuth
        hubGateway = new Gateway(
            HUB_CENTRIFUGE_ID,
            IProtocolPauser(address(root)),
            address(this)
        );
        hubMultiAdapter = new MultiAdapter(
            HUB_CENTRIFUGE_ID,
            IMessageHandler(address(hubGateway)),
            address(this)
        );
        hubMessageProcessor = new MessageProcessor(
            IScheduleAuth(address(root)),
            address(this)
        );
        hubMessageDispatcher = new MessageDispatcher(
            HUB_CENTRIFUGE_ID,
            IScheduleAuth(address(root)),
            IGateway(address(hubGateway)),
            address(this)
        );
        hubGasService = new GasService();

        // -----------------------------------------------------------------
        // 3. Deploy Spoke Messaging Stack
        // -----------------------------------------------------------------
        spokeGateway = new Gateway(
            SPOKE_CENTRIFUGE_ID,
            IProtocolPauser(address(root)),
            address(this)
        );
        spokeMultiAdapter = new MultiAdapter(
            SPOKE_CENTRIFUGE_ID,
            IMessageHandler(address(spokeGateway)),
            address(this)
        );
        spokeMessageProcessor = new MessageProcessor(
            IScheduleAuth(address(root)),
            address(this)
        );
        spokeMessageDispatcher = new MessageDispatcher(
            SPOKE_CENTRIFUGE_ID,
            IScheduleAuth(address(root)),
            IGateway(address(spokeGateway)),
            address(this)
        );
        spokeGasService = new GasService();

        // -----------------------------------------------------------------
        // 4. Deploy Bridge Adapters
        // -----------------------------------------------------------------
        adapterHubToSpoke = new SimplifiedLocalAdapter(
            HUB_CENTRIFUGE_ID,
            IMessageHandler(address(hubMultiAdapter)),
            address(this)
        );
        adapterSpokeToHub = new SimplifiedLocalAdapter(
            SPOKE_CENTRIFUGE_ID,
            IMessageHandler(address(spokeMultiAdapter)),
            address(this)
        );
        adapterHubToSpoke.setEndpoint(IMessageHandler(address(adapterSpokeToHub)));
        adapterSpokeToHub.setEndpoint(IMessageHandler(address(adapterHubToSpoke)));

        // -----------------------------------------------------------------
        // 5. Deploy Hub Core Contracts
        // -----------------------------------------------------------------
        hubRegistry = new HubRegistry(address(this));
        accounting = new Accounting(address(this));
        holdings = new Holdings(IHubRegistry(address(hubRegistry)), address(this));
        shareClassManager = new ShareClassManager(IHubRegistry(address(hubRegistry)), address(this));

        hub = new Hub(
            IGateway(address(hubGateway)),
            IHoldings(address(holdings)),
            IAccounting(address(accounting)),
            IHubRegistry(address(hubRegistry)),
            IMultiAdapter(address(hubMultiAdapter)),
            IShareClassManager(address(shareClassManager)),
            address(this)
        );

        hubHandler = new HubHandler(
            IHub(address(hub)),
            IHoldings(address(holdings)),
            IHubRegistry(address(hubRegistry)),
            IShareClassManager(address(shareClassManager)),
            address(this)
        );

        brm = new BatchRequestManager(
            IHubRegistry(address(hubRegistry)),
            IGateway(address(hubGateway)),
            address(this)
        );

        identityValuation = new IdentityValuation(IHubRegistry(address(hubRegistry)));
        oracleValuation = new OracleValuation(IHub(address(hub)), IHubRegistry(address(hubRegistry)));
        navManager = new NAVManager(IHub(address(hub)));

        // -----------------------------------------------------------------
        // 6. Deploy Spoke Core Contracts
        // -----------------------------------------------------------------
        tokenFactory = new TokenFactory(address(root), address(this));
        poolEscrowFactory = new PoolEscrowFactory(address(root), address(this));
        refundEscrowFactory = new RefundEscrowFactory(address(this));

        spoke = new Spoke(ITokenFactory(address(tokenFactory)), address(this));

        balanceSheet = new BalanceSheet(IEndorsements(address(root)), address(this));

        vaultRegistry = new VaultRegistry(address(this));

        asyncRequestManager = new AsyncRequestManager(
            IEscrow(address(escrow)),
            IRefundEscrowFactory(address(refundEscrowFactory)),
            address(this)
        );

        syncManager = new SyncManager(address(this));

        vaultFactory = new AsyncVaultFactory(
            address(root),
            IAsyncRequestManager(address(asyncRequestManager)),
            address(this)
        );

        fullRestrictions = new FullRestrictions(
            address(root),
            address(spoke),
            address(balanceSheet), // redeemSource
            address(escrow),       // depositTarget
            address(spoke),        // crosschainSource
            address(this)
        );

        // -----------------------------------------------------------------
        // 7. Wire Hub Messaging
        // -----------------------------------------------------------------
        hubGateway.file("processor", address(hubMessageProcessor));
        hubGateway.file("adapter", address(hubMultiAdapter));
        hubGateway.file("messageLimits", address(hubGasService));

        hubMultiAdapter.file("messageProperties", address(hubMessageProcessor));

        hubMessageProcessor.file("gateway", address(hubGateway));
        hubMessageProcessor.file("multiAdapter", address(hubMultiAdapter));
        hubMessageProcessor.file("hubHandler", address(hubHandler));

        hubMessageDispatcher.file("gateway", address(hubGateway));
        hubMessageDispatcher.file("hubHandler", address(hubHandler));

        // Hub messaging relies (from CoreDeployer.engageCore pattern)
        hubGateway.rely(address(hubMultiAdapter));
        hubGateway.rely(address(hubMessageDispatcher));
        hubGateway.rely(address(hubMessageProcessor));
        hubGateway.rely(address(root));
        hubMultiAdapter.rely(address(hubGateway));
        hubMultiAdapter.rely(address(hubMessageProcessor));
        hubMessageProcessor.rely(address(hubGateway));
        hubHandler.rely(address(hubMessageProcessor));
        hubHandler.rely(address(hubMessageDispatcher));
        hubMessageDispatcher.rely(address(hub));
        hubMessageDispatcher.rely(address(hubHandler));

        // -----------------------------------------------------------------
        // 8. Wire Spoke Messaging
        // -----------------------------------------------------------------
        spokeGateway.file("processor", address(spokeMessageProcessor));
        spokeGateway.file("adapter", address(spokeMultiAdapter));
        spokeGateway.file("messageLimits", address(spokeGasService));

        spokeMultiAdapter.file("messageProperties", address(spokeMessageProcessor));

        spokeMessageProcessor.file("gateway", address(spokeGateway));
        spokeMessageProcessor.file("multiAdapter", address(spokeMultiAdapter));
        spokeMessageProcessor.file("spoke", address(spoke));
        spokeMessageProcessor.file("balanceSheet", address(balanceSheet));
        spokeMessageProcessor.file("vaultRegistry", address(vaultRegistry));

        spokeMessageDispatcher.file("gateway", address(spokeGateway));
        spokeMessageDispatcher.file("spoke", address(spoke));
        spokeMessageDispatcher.file("balanceSheet", address(balanceSheet));
        spokeMessageDispatcher.file("vaultRegistry", address(vaultRegistry));

        // Spoke messaging relies (from CoreDeployer.engageCore pattern)
        spokeGateway.rely(address(spokeMultiAdapter));
        spokeGateway.rely(address(spokeMessageDispatcher));
        spokeGateway.rely(address(spokeMessageProcessor));
        spokeGateway.rely(address(spoke));
        spokeGateway.rely(address(root));
        spokeMultiAdapter.rely(address(spokeGateway));
        spokeMultiAdapter.rely(address(spokeMessageProcessor));
        spokeMessageProcessor.rely(address(spokeGateway));
        spoke.rely(address(spokeMessageProcessor));
        spoke.rely(address(spokeMessageDispatcher));
        balanceSheet.rely(address(spokeMessageProcessor));
        vaultRegistry.rely(address(spokeMessageProcessor));
        spokeMessageDispatcher.rely(address(spoke));
        spokeMessageDispatcher.rely(address(balanceSheet));
        spokeMessageDispatcher.rely(address(vaultRegistry));

        // -----------------------------------------------------------------
        // 9. Wire Hub Core Dependencies
        // -----------------------------------------------------------------
        hub.file("sender", address(hubMessageDispatcher));
        hubHandler.file("sender", address(hubMessageDispatcher));
        brm.file("hub", address(hub));

        // Hub rely: Hub ↔ sub-contracts
        hubRegistry.rely(address(hub));
        accounting.rely(address(hub));
        holdings.rely(address(hub));
        shareClassManager.rely(address(hub));

        hubRegistry.rely(address(hubHandler));
        holdings.rely(address(hubHandler));
        shareClassManager.rely(address(hubHandler));
        hub.rely(address(hubHandler));

        hubRegistry.rely(address(brm));
        hub.rely(address(brm));
        hub.rely(address(hub)); // self-rely for internal calls

        // -----------------------------------------------------------------
        // 10. Wire Spoke Core Dependencies
        // -----------------------------------------------------------------
        spoke.file("gateway", address(spokeGateway));
        spoke.file("sender", address(spokeMessageDispatcher));
        spoke.file("poolEscrowFactory", address(poolEscrowFactory));

        balanceSheet.file("spoke", address(spoke));
        balanceSheet.file("sender", address(spokeMessageDispatcher));
        balanceSheet.file("gateway", address(spokeGateway));
        balanceSheet.file("poolEscrowProvider", address(poolEscrowFactory));

        asyncRequestManager.file("spoke", address(spoke));
        asyncRequestManager.file("vaultRegistry", address(vaultRegistry));
        asyncRequestManager.file("balanceSheet", address(balanceSheet));

        syncManager.file("spoke", address(spoke));
        syncManager.file("vaultRegistry", address(vaultRegistry));
        syncManager.file("balanceSheet", address(balanceSheet));

        vaultRegistry.file("spoke", address(spoke));

        poolEscrowFactory.file("gateway", address(spokeGateway));
        poolEscrowFactory.file("balanceSheet", address(balanceSheet));

        refundEscrowFactory.file("controller", address(asyncRequestManager));
        refundEscrowFactory.file("root", address(root));

        // TokenFactory wards for created tokens
        address[] memory tokenWards = new address[](2);
        tokenWards[0] = address(balanceSheet);
        tokenWards[1] = address(spoke);
        tokenFactory.file("wards", tokenWards);

        // Spoke rely: core sub-contracts
        asyncRequestManager.rely(address(spoke));
        asyncRequestManager.rely(address(vaultFactory));
        spoke.rely(address(vaultRegistry));
        balanceSheet.rely(address(asyncRequestManager));
        balanceSheet.rely(address(syncManager));
        escrow.rely(address(asyncRequestManager));
        escrow.rely(address(spoke));
        escrow.rely(address(balanceSheet));
        fullRestrictions.rely(address(spoke));
        vaultRegistry.rely(address(spoke));
        vaultFactory.rely(address(vaultRegistry));
        tokenFactory.rely(address(spoke));
        poolEscrowFactory.rely(address(spoke));
        refundEscrowFactory.rely(address(asyncRequestManager));

        // Root endorsements (bypasses FullRestrictions transfer hooks)
        root.endorse(address(escrow));
        root.endorse(address(balanceSheet));
        root.endorse(address(spoke));
        root.endorse(address(asyncRequestManager));

        // -----------------------------------------------------------------
        // 11. Deploy QueueManager (needs BalanceSheet gateway wired first)
        // -----------------------------------------------------------------
        queueManager = new QueueManager(address(this), IBalanceSheet(address(balanceSheet)), address(this));
        balanceSheet.rely(address(queueManager));

        // -----------------------------------------------------------------
        // 12. Set Adapters on MultiAdapters
        // -----------------------------------------------------------------
        _setupAdapters();
    }

    /// @dev Register cross-chain adapters on both MultiAdapters
    function _setupAdapters() internal {
        // Hub → Spoke route
        IAdapter[] memory hubAdapters = new IAdapter[](1);
        hubAdapters[0] = IAdapter(address(adapterHubToSpoke));
        hubMultiAdapter.setAdapters(
            SPOKE_CENTRIFUGE_ID,
            PoolId.wrap(0), // GLOBAL_POOL — applies to all pools
            hubAdapters,
            1, // threshold: 1 of 1 adapters
            1  // recoveryIndex: 1 (no recovery, since index >= length)
        );

        // Spoke → Hub route
        IAdapter[] memory spokeAdapters = new IAdapter[](1);
        spokeAdapters[0] = IAdapter(address(adapterSpokeToHub));
        spokeMultiAdapter.setAdapters(
            HUB_CENTRIFUGE_ID,
            PoolId.wrap(0), // GLOBAL_POOL
            spokeAdapters,
            1,
            1
        );
    }

    // ===================================================================
    // Helpers
    // ===================================================================

    /// @dev Returns a random actor
    function _getRandomActor(uint256 entropy) internal view returns (address) {
        address[] memory actorsArray = _getActors();
        return actorsArray[entropy % actorsArray.length];
    }

    /// @dev Returns a random pool from createdPools
    function _getRandomPoolId(uint64 poolEntropy) internal view returns (PoolId) {
        require(createdPools.length > 0, "No pools");
        return createdPools[poolEntropy % createdPools.length];
    }

    /// @dev Returns a random share class for a given pool
    function _getRandomShareClassId(PoolId poolId, uint32 scEntropy) internal view returns (ShareClassId) {
        ShareClassId[] storage scs = poolShareClasses[poolId];
        require(scs.length > 0, "No share classes");
        return scs[scEntropy % scs.length];
    }
}
