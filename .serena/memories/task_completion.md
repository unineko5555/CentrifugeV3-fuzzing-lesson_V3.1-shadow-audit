# Task Completion Checklist

When completing a task in this project, follow these steps:

## After Code Changes
1. **Build check**: `forge build` -- ensure compilation succeeds
2. **Format check**: `forge fmt --check` -- verify formatting compliance
3. **Run affected tests**: `forge test --match-path "test/<affected_module>/*.t.sol"` -- run relevant unit tests
4. **Run integration tests**: `forge test --match-path "test/integration/*.t.sol"` -- run integration suite
5. **Static analysis (optional)**: `slither . --config-file slither.config.json`

## Code Review Checklist
- [ ] No new custom errors without proper documentation
- [ ] All `auth`-gated functions have proper ward requirements documented
- [ ] No unsafe external calls without reentrancy protection (transient storage guard or auth checks)
- [ ] Double-entry accounting invariant maintained (debits == credits within unlock/lock scope)
- [ ] Cross-chain message encoding matches the MessageLib format exactly
- [ ] D18 arithmetic checked for overflow (uint128 max ~3.4e38)
- [ ] Transfer restrictions properly checked before share token operations
- [ ] Price staleness (`maxAge`) handled correctly
- [ ] Nonce ordering maintained for snapshot state updates
- [ ] Factory CREATE2 salts are unique and deterministic

## Audit-Specific Tasks
- For this project (Sherlock audit contest), focus on:
  - Finding High/Medium severity vulnerabilities
  - The codebase has 19 prior security reviews
  - Known issues are listed in the contest README (not valid findings)
  - Key areas: cross-chain messaging, vault flows, accounting invariants, price manipulation, access control
