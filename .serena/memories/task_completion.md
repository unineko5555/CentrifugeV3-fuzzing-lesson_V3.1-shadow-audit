# Task Completion Checklist

## After Completing Code Changes

### 1. Formatting
```bash
forge fmt
```
- Automatically formats all Solidity files according to project conventions
- Required before committing code changes

### 2. Building
```bash
forge build
```
- Ensures all contracts compile successfully
- Catches compilation errors early
- Verifies imports and dependencies

### 3. Testing
```bash
forge test
```
- Run the full test suite
- Ensure all existing tests still pass
- For specific tests: `forge test --match-test testName`
- For verbose output: `forge test -vvv`

### 4. Gas Analysis (Optional but Recommended)
```bash
forge snapshot
```
- Creates/updates gas snapshots
- Helps track gas optimization improvements
- Compare with: `forge snapshot --diff`

### 5. Static Analysis (Recommended for Security Tasks)
```bash
slither . --config-file slither.config.json
```
- Run static analysis to catch common vulnerabilities
- Note: Some detectors are excluded per project config

### 6. Coverage (For New Features)
```bash
forge coverage
```
- Check test coverage for new code
- Aim for high coverage on critical paths

## Before Submitting Audit Findings

### Verify the Issue
1. Write a proof-of-concept test demonstrating the vulnerability
2. Run the test to confirm it fails/succeeds as expected
3. Check if it's in the known issues list (README.md lines 68-92)

### Check Severity
Per Sherlock guidelines:
- **High**: Permanent loss/lock of funds with no recovery
- **Medium**: Temporary DOS, hook bypass, price manipulation, native token issues
- **Out of Scope**: Network compromise, specific known issues

### Document the Finding
Use the issue template at `.github/ISSUE_TEMPLATE/audit-report.yml`

## Best Practices for This Audit

1. **Read Documentation First**
   - https://v3-1.documentation-569.pages.dev/developer/protocol/overview/
   - Focus on new features in v3.1 vs v3.0.1

2. **Focus Areas**
   - Pool manager cross-pool manipulation
   - Cross-chain message handling
   - SimplePriceManager price manipulation
   - Transfer hooks and compliance bypasses

3. **Test Thoroughly**
   - Write tests for edge cases
   - Test cross-chain scenarios
   - Test access control boundaries
   - Fuzz test critical functions

4. **Check EIP Compliance**
   - ERC-20, ERC-1404, ERC-2612, ERC-4626, ERC-6909, ERC-7540, ERC-7575
   - Only report if non-compliance leads to Medium/High impact

## Common Workflow

```bash
# After making changes
forge fmt                    # Format
forge build                  # Compile
forge test                   # Test
forge test -vvv             # Verbose test (if failures)
forge snapshot              # Update gas snapshots
slither .                   # Static analysis

# For specific tests
forge test --match-path test/core/hub/Hub.t.sol -vvv
forge test --match-test testSpecificFunction -vvvv
```

## Notes
- This is an **audit repository** - focus is on finding issues, not shipping features
- Always check against known issues list before reporting
- Consider cross-chain implications for all findings
- Test with different chain configurations (Ethereum, Base, Arbitrum, etc.)
