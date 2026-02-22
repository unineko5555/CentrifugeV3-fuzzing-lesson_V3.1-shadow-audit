# Repository Guidelines

## Project Structure & Module Organization

All Solidity sources live in `protocol/src`, split by domain: hub/spoke core logic, adapters, managers, valuations, vaults, hooks, and shared misc utilities. Tests mirror this layout under `protocol/test`, with integration and fuzz suites grouped per module. Deployment helpers sit in `protocol/script`, reference data in `protocol/env`, and gas metrics in `protocol/snapshots`. Project-wide compiler, fuzzing, and formatting defaults live in `protocol/foundry.toml`.

## Build, Test & Development Commands

Run commands from the `protocol` directory. Use `forge build` to compile with solc 0.8.28 and the configured optimizer, and `forge test` to execute the full unit, integration, fuzz, and invariant suites. Target specific scopes with `forge test --match-path test/<module>/<pattern>.t.sol` when iterating quickly. Refresh gas baselines via `forge snapshot`, and execute automation or deployment scripts with `forge script script/<Script>.s.sol --rpc-url <network> --broadcast`. For static analysis, run `slither . --config-file slither.config.json`.

## Coding Style & Naming Conventions

Format Solidity with `forge fmt`; it enforces 4-space indentation, a 120-character line limit, long-form integer suffixes, and double-quoted strings. Name contracts and libraries after their module (e.g., `HubBalanceSheet`, `SpokeQueueManager`) and keep test contracts aligned with the target (`Foo.t.sol`, `FooInvariant.t.sol`). Favor small, composable contracts placed alongside peers in their module directory, and avoid manual edits to generated snapshots.

## Testing Guidelines

Default fuzz runs (100) and invariant runs (10, depth 100) come from `foundry.toml`; bump them locally if a fix relies on edge coverage. Place new unit tests beside the related module path, and add integration scenarios under `test/integration` when behavior spans components. Before submitting, run `forge test`; add `forge coverage --report lcov` and review gas snapshots whenever logic or performance-sensitive paths change.

## Commit & Pull Request Guidelines

Write commits in imperative mood with an optional scope prefix mirroring the module (e.g., `vaults: guard async withdrawals`). Include a concise body describing rationale and side effects when needed. Pull requests should summarize the change, link Sherlock issues or audit findings, list test commands run, and note any gas snapshot or configuration updates. Provide screenshots or logs only when manual steps influence the review.

## Security & Configuration Notes

FFI and filesystem permissions are enabled for fixtures in `env/latest`; keep these artifacts trusted and document any new files they depend on. Review cross-chain assumptions when touching adapters or messaging contracts, and call out new trust requirements in PR descriptions. Never commit secrets; reference `.env` paths instead and sanitize local data before sharing.
