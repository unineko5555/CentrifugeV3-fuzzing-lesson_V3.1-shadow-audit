# Suggested Commands

All commands are run from the `protocol/` directory (or `protocol-v3/` symlink).

## Build
```bash
forge build                    # Compile all contracts (solc 0.8.28, Cancun EVM)
forge build --sizes            # Show contract sizes
```

## Test
```bash
forge test                                              # Run all tests (default: 100 fuzz runs)
forge test --match-path "test/core/hub/*.t.sol"         # Run specific module tests
forge test --match-test "testDeposit"                   # Run specific test function
forge test -vvvv                                        # Verbose output with traces
forge test --ffi                                        # Enable FFI (needed for some tests)

# CI profiles
FOUNDRY_PROFILE=ci forge test                           # CI fuzz: 1000 runs
FOUNDRY_PROFILE=ci-invariant forge test                 # CI invariant: 100 runs, depth 1000
```

## Coverage
```bash
forge coverage                    # Basic coverage
forge coverage --report lcov      # Generate lcov report
```

## Gas Benchmarks
```bash
forge snapshot                    # Generate gas snapshots
forge test --gas-report           # Gas usage report
```

## Formatting
```bash
forge fmt                         # Format Solidity code
forge fmt --check                 # Check formatting without modifying
```

## Static Analysis
```bash
# Slither
slither . --config-file slither.config.json

# Aderyn (from project root, NOT protocol/)
cd .. && aderyn                   # Uses aderyn.toml config (root = "protocol")
```

## Deployment
```bash
forge script script/FullDeployer.s.sol --rpc-url <network> --broadcast
forge script script/CoreDeployer.s.sol --rpc-url <network> --broadcast
forge script script/LaunchDeployer.s.sol --rpc-url <network> --broadcast
```

## System Utilities (Darwin/macOS)
```bash
git status / git diff / git log    # Version control
ls / find / grep                   # File system navigation
python3                            # Python scripts in script/deploy/
```
