# Coding Style and Conventions

## Solidity Version
- **Version**: 0.8.28 (fixed, not ^)
- **EVM**: Cancun
- **License**: Business Source License 1.1 (BSL 1.1)
  - Exception: `src/misc/` folder and interface files can also use GPL-2.0-or-later

## Code Style

### License Headers
```solidity
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;
```

### Contract Documentation
- Use NatSpec comments (`///`) for public/external functions
- Include `@title`, `@notice`, `@author` tags for contracts
- Use `@inheritdoc` for inherited interface functions
- Include `@dev` for implementation details

### Example Style
```solidity
/// @title  Auth
/// @notice Simple authentication pattern
/// @author Based on code from https://github.com/makerdao/dss
abstract contract Auth is IAuth {
    /// @inheritdoc IAuth
    mapping(address => uint256) public wards;
    
    /// @dev Check if the msg.sender has permissions
    modifier auth() {
        require(wards[msg.sender] == 1, NotAuthorized());
        _;
    }
}
```

## Formatting (from foundry.toml)
- **Line length**: 120 characters
- **Tab width**: 4 spaces
- **Bracket spacing**: false (no spaces)
- **Int types**: long format
- **Multiline function header**: attributes_first
- **Quote style**: double quotes
- **Number underscore**: preserve
- **Wrap comments**: false

## Compiler Settings
- **Optimizer**: Enabled (1 run for deployment size optimization)
- **Verbosity**: Level 3
- **FFI**: Enabled (for scripting)
- **Bytecode hash**: none (for deterministic builds)
- **CBOR metadata**: false
- **Use literal content**: true (for verification)

## Naming Conventions
Based on the codebase structure:
- **Contracts**: PascalCase (e.g., `Auth`, `ShareToken`, `AsyncVault`)
- **Interfaces**: IPascalCase (e.g., `IAuth`, `IHub`, `IVault`)
- **Libraries**: PascalCase + "Lib" suffix (e.g., `MathLib`, `BytesLib`, `MessageLib`)
- **Functions**: camelCase (e.g., `rely`, `deny`, `transfer`)
- **Modifiers**: lowercase (e.g., `auth`, `onlyRole`)
- **State variables**: camelCase
- **Constants**: UPPER_SNAKE_CASE
- **Events**: PascalCase (e.g., `Rely`, `Deny`)

## Patterns
- **Auth pattern**: MakerDAO-style ward-based permissions
- **Factory pattern**: Used for vault and escrow deployment
- **Proxy pattern**: Not used (immutable core design)
- **Reentrancy protection**: Custom implementation in `src/misc/ReentrancyProtection.sol`
- **Custom errors**: Preferred over require strings

## Testing Conventions
- Test files in `test/` directory mirroring `src/` structure
- Test file naming: Not included in docs (pattern: `*.t.sol`)
- Script file naming: `*.s.sol`
- Fuzz testing: 100 runs (default), 1000 runs (CI)
- Invariant testing: 10 runs, depth 100 (default); 100 runs, depth 1000 (CI)

## Static Analysis
- **Slither** configuration in `slither.config.json`
- Excluded detectors: naming-convention, reentrancy-events, solc-version, timestamp, name-reused, arbitrary-send-erc20
- Filter paths: lib and test directories
