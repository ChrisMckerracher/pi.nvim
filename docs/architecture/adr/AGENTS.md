# Authorship
- 2026-06-19 23:53 — agent: GLM-5.2 (added provenance header; document content predates this standard)
- 2026-07-18 00:45 — agent: pi (k3) (copied from the pocket doc set; contents index updated with ADR-001..004)

# Architecture Decision Records (ADR)

Immutable records of architectural decisions. Each ADR captures a single decision, the context at the time, and the consequences.

### Format

```
# ADR-NNN: Short Title

## Status
Proposed | Accepted | Deprecated | Superseded by ADR-XXX

## Context
What is the situation that necessitates this decision?

## Decision
What did we decide?

## Consequences
What are the positive and negative outcomes?
```

### Rules

- **Never update** an accepted ADR. Create a new one that supersedes it.
- One decision per ADR.
- Number sequentially: ADR-001, ADR-002, etc.
- File naming: `NNN-short-title.md` (e.g. `001-use-uv-for-package-management.md`).

### Contents

| ADR | Decision |
|-----|----------|
| [001](001-sdk-host-over-cli-embed-or-rpc.md) | Embed pi via a custom TypeScript SDK host, not CLI embed or `pi --mode rpc` |
| [002](002-versioned-jsonl-stdio-protocol.md) | Versioned LF-delimited JSONL protocol over stdio between Lua and host |
| [003](003-reuse-user-pi-config-and-shared-session-store.md) | Reuse the user's `~/.pi/agent` config and session store — no parallel config |
| [004](004-diff-review-via-streamed-patches.md) | Diff review from SDK-streamed `details.patch`, no git plugin |
