// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {AccountId} from "src/core/types/AccountId.sol";
import {JournalEntry} from "src/core/hub/interfaces/IAccounting.sol";
import {Properties} from "../properties/Properties.sol";
import {BeforeAfter, OpType} from "../BeforeAfter.sol";

/// @title JournalTargets
/// @notice Target functions for Hub.updateJournal → Accounting.unlock + addJournal + lock.
///         Uses dedicated journal accounts (not holding-tied) to avoid breaking P-ACC-1/P-NAV-3.
abstract contract JournalTargets is BaseTargetFunctions, Properties {
    /// @dev Dedicated account IDs for journal testing (not tied to any holding)
    ///      Uses high index values (0xFF00/0xFF01) to avoid collision with NAVManager accounts
    AccountId internal constant JOURNAL_DEBIT_ACC = AccountId.wrap(0xFF00);
    AccountId internal constant JOURNAL_CREDIT_ACC = AccountId.wrap(0xFF01);
    bool internal journalAccountsCreated;

    /// @dev Create dedicated journal accounts for the active pool (one-time setup)
    function _ensureJournalAccounts() internal {
        if (journalAccountsCreated) return;

        // Create two independent debit-normal accounts for journal testing
        try hub.createAccount(activePoolId, JOURNAL_DEBIT_ACC, true) {} catch {
            return;
        }
        try hub.createAccount(activePoolId, JOURNAL_CREDIT_ACC, false) {} catch {
            return;
        }
        journalAccountsCreated = true;
    }

    /// @dev Balanced journal: debit/credit dedicated accounts (same amount)
    function journal_balanced(uint128 amount)
        public
        updateGhostsWithType(OpType.JOURNAL_UPDATE)
        poolExists
    {
        amount = _clampU128(amount, 1, uint128(1e24));

        _ensureJournalAccounts();
        if (!journalAccountsCreated) return;

        JournalEntry[] memory debits = new JournalEntry[](1);
        debits[0] = JournalEntry({value: amount, accountId: JOURNAL_DEBIT_ACC});
        JournalEntry[] memory credits = new JournalEntry[](1);
        credits[0] = JournalEntry({value: amount, accountId: JOURNAL_CREDIT_ACC});

        try hub.updateJournal(activePoolId, debits, credits) {
            ghostJournalEntryCount++;
        } catch {}
    }

    /// @dev Reverse journal: credit debit-account, debit credit-account (tests both directions)
    function journal_reverse(uint128 amount)
        public
        updateGhostsWithType(OpType.JOURNAL_UPDATE)
        poolExists
    {
        amount = _clampU128(amount, 1, uint128(1e24));

        _ensureJournalAccounts();
        if (!journalAccountsCreated) return;

        JournalEntry[] memory debits = new JournalEntry[](1);
        debits[0] = JournalEntry({value: amount, accountId: JOURNAL_CREDIT_ACC});
        JournalEntry[] memory credits = new JournalEntry[](1);
        credits[0] = JournalEntry({value: amount, accountId: JOURNAL_DEBIT_ACC});

        try hub.updateJournal(activePoolId, debits, credits) {
            ghostJournalEntryCount++;
        } catch {}
    }

    /// @dev Doomsday: unbalanced journal MUST revert
    function journal_doomsday_unbalanced_reverts(uint128 debitAmt, uint128 creditAmt)
        public
        poolExists
    {
        debitAmt = _clampU128(debitAmt, 1, uint128(1e24));
        creditAmt = _clampU128(creditAmt, 1, uint128(1e24));
        if (debitAmt == creditAmt) return;

        _ensureJournalAccounts();
        if (!journalAccountsCreated) return;

        JournalEntry[] memory debits = new JournalEntry[](1);
        debits[0] = JournalEntry({value: debitAmt, accountId: JOURNAL_DEBIT_ACC});
        JournalEntry[] memory credits = new JournalEntry[](1);
        credits[0] = JournalEntry({value: creditAmt, accountId: JOURNAL_CREDIT_ACC});

        try hub.updateJournal(activePoolId, debits, credits) {
            revert("journal: unbalanced journal did not revert");
        } catch {}
    }
}
