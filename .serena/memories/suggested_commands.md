# Suggested Commands

## Primary Development Commands

### Testing
```bash
# Run all tests
forge test

# Run tests with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/path/to/Test.t.sol

# Run specific test function
forge test --match-test testFunctionName

# Run tests with gas reporting
forge test --gas-report

# Run with coverage
forge coverage

# Run fuzz tests (100 runs default, 1000 in CI)
forge test --fuzz-runs 100

# Run invariant tests
forge test --invariant-runs 10 --invariant-depth 100
```

### Building
```bash
# Build the project
forge build

# Build with specific profile
forge build --profile ci

# Clean build artifacts
forge clean
```

### Formatting
```bash
# Format all Solidity files
forge fmt

# Check formatting without modifying
forge fmt --check
```

### Linting
```bash
# Lint Solidity files
forge lint

# Run Slither static analysis
slither . --config-file slither.config.json
```

### Documentation
```bash
# Generate documentation
forge doc

# Build docs to docs/ directory
forge doc --out docs
```

### Gas Analysis
```bash
# Create gas snapshot
forge snapshot

# Compare gas snapshots
forge snapshot --diff

# Gas report (automatically included in tests)
forge test --gas-report
```

### Other Useful Commands
```bash
# Display remappings
forge remappings

# Inspect contract
forge inspect ContractName abi
forge inspect ContractName storage

# Flatten contract (for verification)
forge flatten src/path/to/Contract.sol

# Check config
forge config

# Display dependency tree
forge tree
```

## Git Commands (macOS/Darwin)
```bash
# Standard git operations
git status
git add <files>
git commit -m "message"
git push
git pull

# Branch operations
git branch
git checkout -b <branch-name>
git switch <branch-name>

# Viewing changes
git diff
git log --oneline
```

## File Operations (macOS/Darwin)
```bash
# List files
ls -la

# Find files
find . -name "*.sol"
find . -type f -name "pattern"

# Search in files (use ripgrep if available, otherwise grep)
rg "pattern" --type sol
grep -r "pattern" src/

# File viewing
cat <file>
head -n 20 <file>
tail -n 20 <file>
less <file>

# Directory navigation
cd <path>
pwd
```

## Project-Specific Notes
- Working directory: `/Users/s.p./Desktop/Web3_Dev/Cyfrin_Updraft/audit/2025-10-centrifuge-protocol-v3-1-audit-unineko5555/protocol`
- This is an **audit repository** - focus on testing and analysis, not deployment
- FFI is enabled for scripting purposes
- Multiple test profiles available: default, ci, ci-coverage, smt
