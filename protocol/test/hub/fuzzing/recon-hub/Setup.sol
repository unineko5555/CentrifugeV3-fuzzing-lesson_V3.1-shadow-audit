// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

// Chimera deps
import {BaseSetup} from "@chimera/BaseSetup.sol";
import {vm} from "@chimera/Hevm.sol";
import {console2} from "forge-std/console2.sol";

// Recon Helpers
import {ActorManager} from "@recon/ActorManager.sol";
import {AssetManager} from "@recon/AssetManager.sol";
import {Utils} from "@recon/Utils.sol";

// Core contracts
import {Hub} from "src/core/hub/Hub.sol";
import {Accounting} from "src/core/hub/Accounting.sol";
import {Holdings} from "src/core/hub/Holdings.sol";
import {HubRegistry} from "src/core/hub/HubRegistry.sol";
import {HubHandler} from "src/core/hub/HubHandler.sol";
import {ShareClassManager} from "src/core/hub/ShareClassManager.sol";

// Vault contracts
import {BatchRequestManager} from "src/vaults/BatchRequestManager.sol";

// Manager contracts
import {NAVManager} from "src/managers/hub/NAVManager.sol";

// Valuation contracts
import {IdentityValuation} from "src/valuations/IdentityValuation.sol";
import {OracleValuation} from "src/valuations/OracleValuation.sol";
import {MockValuation} from "test/core/mocks/MockValuation.sol";

// Interfaces
import {IGateway} from "src/core/messaging/interfaces/IGateway.sol";
import {IHub} from "src/core/hub/interfaces/IHub.sol";
import {IHoldings} from "src/core/hub/interfaces/IHoldings.sol";
import {IAccounting, JournalEntry} from "src/core/hub/interfaces/IAccounting.sol";
import {IHubRegistry} from "src/core/hub/interfaces/IHubRegistry.sol";
import {IShareClassManager} from "src/core/hub/interfaces/IShareClassManager.sol";
import {IMultiAdapter} from "src/core/messaging/interfaces/IMultiAdapter.sol";
import {IHubMessageSender} from "src/core/messaging/interfaces/IGatewaySenders.sol";
import {IHubRequestManager} from "src/core/hub/interfaces/IHubRequestManager.sol";
import {IValuation} from "src/core/hub/interfaces/IValuation.sol";

// Types
import {PoolId} from "src/core/types/PoolId.sol";
import {AssetId, newAssetId} from "src/core/types/AssetId.sol";
import {AccountId} from "src/core/types/AccountId.sol";
import {ShareClassId} from "src/core/types/ShareClassId.sol";
import {D18, d18} from "src/misc/types/D18.sol";

// Mocks
import {MockGateway} from "./mocks/MockGateway.sol";
import {MockMultiAdapter} from "./mocks/MockMultiAdapter.sol";
import {MockMessageSender} from "./mocks/MockMessageSender.sol";
import {MockSpoke} from "./mocks/MockSpoke.sol";
import {MockBalanceSheet} from "./mocks/MockBalanceSheet.sol";

abstract contract Setup is BaseSetup, ActorManager, AssetManager, Utils {
    // Core contracts
    Hub public hub;
    Accounting public accounting;
    Holdings public holdings;
    HubRegistry public hubRegistry;
    HubHandler public hubHandler;
    ShareClassManager public shareClassManager;

    // Vault contracts
    BatchRequestManager public brm;

    // Manager contracts
    NAVManager public navManager;

    // Valuations
    IdentityValuation public identityValuation;
    OracleValuation public oracleValuation;
    MockValuation public mockValuation;

    // Mocks
    MockGateway public gateway;
    MockMultiAdapter public multiAdapter;
    MockMessageSender public messageSender;
    MockSpoke public spoke;
    MockBalanceSheet public balanceSheet;

    // Test state
    bytes[] internal queuedCalls;
    PoolId[] internal createdPools;
    AccountId[] internal createdAccountIds;
    AssetId[] internal createdAssetIds;

    // Canaries
    bool poolCreated;
    bool deposited;

    // Constants & toggles
    D18 internal INITIAL_PRICE = d18(1e18);
    uint16 internal CENTRIFUGE_CHAIN_ID = 1;
    bool internal IS_LIABILITY = true;
    bool internal IS_INCREASE = true;
    bool internal IS_DEBIT_NORMAL = true;
    bool internal IS_SNAPSHOT = false;
    uint64 internal NONCE = 0;
    uint32 internal MAX_CLAIMS = 10;
    AccountId internal ACCOUNT_TO_UPDATE = AccountId.wrap(0);
    uint32 internal ASSET_ACCOUNT = 1;
    uint32 internal EQUITY_ACCOUNT = 2;
    uint32 internal LOSS_ACCOUNT = 3;
    uint32 internal GAIN_ACCOUNT = 4;
    uint64 internal POOL_ID_COUNTER = 1;
    uint32 internal NOW_EPOCH_ID = 0;

    event LogString(string);

    modifier statelessTest() {
        _;
        revert("stateless");
    }

    modifier clearQueuedCalls() {
        queuedCalls = new bytes[](0);
        _;
    }

    /// === Setup === ///
    function setup() internal virtual override {
        // Add actors
        _addActor(address(0x10000));
        _addActor(address(0x20000));

        // Deploy mocks first (no dependencies)
        gateway = new MockGateway();
        multiAdapter = new MockMultiAdapter();
        messageSender = new MockMessageSender(CENTRIFUGE_CHAIN_ID);
        spoke = new MockSpoke();
        balanceSheet = new MockBalanceSheet();

        // Deploy core contracts (in dependency order)
        hubRegistry = new HubRegistry(address(this));
        accounting = new Accounting(address(this));
        holdings = new Holdings(IHubRegistry(address(hubRegistry)), address(this));
        shareClassManager = new ShareClassManager(IHubRegistry(address(hubRegistry)), address(this));

        // Deploy Hub
        hub = new Hub(
            IGateway(address(gateway)),
            IHoldings(address(holdings)),
            IAccounting(address(accounting)),
            IHubRegistry(address(hubRegistry)),
            IMultiAdapter(address(multiAdapter)),
            IShareClassManager(address(shareClassManager)),
            address(this)
        );

        // Deploy HubHandler
        hubHandler = new HubHandler(
            IHub(address(hub)),
            IHoldings(address(holdings)),
            IHubRegistry(address(hubRegistry)),
            IShareClassManager(address(shareClassManager)),
            address(this)
        );

        // Deploy BatchRequestManager
        brm = new BatchRequestManager(
            IHubRegistry(address(hubRegistry)),
            IGateway(address(gateway)),
            address(this)
        );

        // Deploy valuations
        identityValuation = new IdentityValuation(IHubRegistry(address(hubRegistry)));
        mockValuation = new MockValuation(IHubRegistry(address(hubRegistry)));
        oracleValuation = new OracleValuation(IHub(address(hub)), IHubRegistry(address(hubRegistry)));

        // Deploy NAVManager (depends on hub)
        navManager = new NAVManager(IHub(address(hub)));

        // === Permission wiring ===

        // Hub needs auth on registry, accounting, holdings, shareClassManager
        hubRegistry.rely(address(hub));
        accounting.rely(address(hub));
        holdings.rely(address(hub));
        shareClassManager.rely(address(hub));

        // HubHandler needs auth on registry, holdings, shareClassManager, hub
        hubRegistry.rely(address(hubHandler));
        holdings.rely(address(hubHandler));
        shareClassManager.rely(address(hubHandler));
        hub.rely(address(hubHandler));

        // BatchRequestManager needs auth on hubRegistry (for manager checks)
        hubRegistry.rely(address(brm));

        // Hub self-rely for internal calls
        hub.rely(address(hub));

        // Set Hub's message sender
        hub.file("sender", address(messageSender));

        // Set HubHandler's sender for cross-chain replies
        hubHandler.file("sender", address(messageSender));

        // BatchRequestManager: set hub reference
        brm.file("hub", address(hub));

        // Keep shareClassManager rely for test contract (admin)
        shareClassManager.rely(address(this));
    }

    /// === Modifiers === ///
    modifier asAdmin() {
        vm.prank(address(this));
        _;
    }

    modifier asActor() {
        vm.prank(address(_getActor()));
        _;
    }

    /// === Helpers === ///
    function _getRandomPoolId(uint64 poolEntropy) internal view returns (PoolId) {
        return createdPools[poolEntropy % createdPools.length];
    }

    function _getRandomShareClassIdForPool(PoolId poolId, uint32 scEntropy) internal view returns (ShareClassId) {
        uint32 shareClassCount = shareClassManager.shareClassCount(poolId);
        uint32 randomIndex = scEntropy % shareClassCount;
        if (randomIndex == 0) {
            randomIndex = 1;
        }
        ShareClassId scId = shareClassManager.previewShareClassId(poolId, randomIndex);
        return scId;
    }

    function _getRandomAccountId(PoolId poolId, ShareClassId scId, AssetId assetId, uint8 accountEntropy)
        internal
        view
        returns (AccountId)
    {
        uint8 accountType = accountEntropy % 6;
        return holdings.accountId(poolId, scId, assetId, accountType);
    }

    function _getRandomAssetId(uint128 assetEntropy) internal view returns (AssetId) {
        uint256 randomIndex = assetEntropy % createdAssetIds.length;
        return createdAssetIds[randomIndex];
    }
}
