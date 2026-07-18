# Authorship
- 2026-06-19 23:53 — agent: GLM-5.2 (added provenance header; document content predates this standard)
- 2026-07-18 00:45 — agent: pi (k3) (copied from the pocket doc set; adapted from pytest/pytest-cov to vitest + plenary)
- 2026-07-18 01:40 — agent: pi (k3) (rule 4 added: e2e runs share real config state — pi persists thinking level per cwd; reset what you change)

# Testing Standards

1. Add unit tests for domain logic and boundary behavior — protocol framing is a boundary and is always tested.
2. Add regression tests for every production bug fix.
3. Keep tests deterministic where possible. Host unit tests never hit the network: use the pi SDK's in-memory factories (`SessionManager.inMemory()`, `SettingsManager.inMemory()`); provider calls are integration tests and must be tagged/skippable.
4. E2E runs against the real `~/.pi/agent` config share its state — pi persists the last-used thinking level per cwd, so a test that cycles thinking changes what the next session restores. Reset what you change before finishing.
4. Diagnose the real cause of a failing test before changing code or tests.
5. Do not weaken contracts or mask failures just to get tests passing.
6. Keep test code to the same clarity and maintainability bar as production code.

## Coverage

- Host: vitest with v8 coverage (`npm test --prefix host`; coverage config arrives with the first domain module beyond protocol framing).
- Lua: plenary busted-style; harness arrives with the first real Lua module (Phase 1). Until then, Lua is covered by stylua/selene via `make lint`.

## Test Organization

- Host tests live in `host/test/`, named `*.test.ts`.
- Lua tests live in `tests/`, named `*_spec.lua`.
- Keep test artifacts (fixtures, data) separate from test logic.
