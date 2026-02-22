# Code Style and Conventions

## Solidity Version & Compiler
- Solidity `0.8.28` with Cancun EVM target
- Optimizer enabled with **1 run** (optimized for deployment size)
- Bytecode hash: `none`, CBOR metadata disabled

## Formatting (foundry.toml [fmt])
- **4-space indentation**
- **120-character line limit**
- Long-form integer types: `uint256` not `uint`
- Double-quoted strings
- Bracket spacing disabled
- Multiline function header: attributes first
- Number underscores: preserved
- Tests excluded from formatting (`test/*.sol`)

## Naming Conventions
- Contract naming: Module-based (e.g., `HubBalanceSheet`, `SpokeQueueManager`)
- Test files: `Foo.t.sol`, `FooInvariant.t.sol`
- Internal variables: `_prefixed` with underscore
- Transient variables: `transient` keyword (EIP-1153 native support)
- Custom types: `type Name is baseType` with global operator overloads (e.g., `D18`, `PoolId`, `AssetId`)
- Libraries: `FooLib` suffix (e.g., `MessageLib`, `PricingLib`, `SafeTransferLib`)
- Interfaces: `IFoo` prefix
- Factory pattern: `FooFactory` with CREATE2 deterministic deployment

## Access Control Pattern
- **MakerDAO ward pattern** (`Auth.sol`): `wards[address] = 1` grants full access
- `rely(address)` / `deny(address)` for management
- `auth` modifier for ward-gated functions
- `_isManager(poolId)` for pool-level access control
- `authOrHook` modifier for hook-related operations

## Error Handling
- Custom errors preferred over require strings
- ERC-7751 `WrappedError` pattern for rich error context in external calls
- No try/catch except in governance contracts (Safe.isOwner)

## Common Patterns
- **BatchedMulticall**: Wraps operations in gateway batch for aggregated cross-chain messages
- **Transient Storage (EIP-1153)**: Used for reentrancy protection, batch state, price overrides, accounting accumulators, queue deduplication
- **unlock/lock**: Accounting pattern ensuring balanced double-entry journal entries
- **Compact storage packing**: e.g., ShareToken Balance = uint128 amount + bytes16 hookData in single slot
- **Factory + CREATE2**: Deterministic deployment with salt-based addressing

## Dependencies
- `forge-std` (test framework)
- `@chimera` (fuzzing framework)
- No external Solidity libraries (all math/utility code is custom)

## Remappings
```
forge-std/=lib/forge-std/src/
@chimera/=lib/chimera/src/
```

## Commit Style
- Imperative mood with optional scope prefix
- Example: `vaults: guard async withdrawals`
