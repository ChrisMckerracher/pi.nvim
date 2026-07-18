# Authorship
- 2026-06-19 23:53 — agent: GLM-5.2 (added provenance header; document content predates this standard)
- 2026-07-18 00:45 — agent: pi (k3) (copied from the pocket doc set; verification gate adapted to `make check`)

# Coding Checklist

Adapted from the CODEX before/during/after pattern.

## Before Coding

1. Confirm requirements and acceptance criteria.
2. Confirm interface and schema impact (protocol changes: bump `PROTOCOL_VERSION`, update ADR-002 references).
3. Confirm test strategy.

## During Coding

1. Follow typing, validation, and security standards ([typescript.md](typescript.md), [lua.md](lua.md), [security.md](security.md)).
2. Keep side effects explicit and observable.
3. Keep auth, tracing, metrics, and logging hooks integrated where applicable.
4. Follow the shared abstraction rules from [engineering.md](engineering.md) — centralize shared concerns, prefer decorators for repeated boundaries.

## After Coding

1. Update tests (unit + regression for bug fixes).
2. Update contracts and schemas when changed (`host/src/protocol.ts` is the protocol contract).
3. Update docs for behavior, contract, or convention changes.
4. Run `make check` before finalizing.
