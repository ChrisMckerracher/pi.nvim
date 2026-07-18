# Authorship
- 2026-06-19 23:53 — agent: GLM-5.2 (added provenance header; document content predates this standard)
- 2026-07-18 00:45 — agent: pi (k3) (copied from the pocket doc set; repo reference updated to pi.nvim)

# Architecture

This folder holds all architectural knowledge for pi.nvim. It follows a three-stage flow:

```
iteration/ → design/ → adr/
```

1. **[iteration/](iteration/AGENTS.md)** — Rough thinking, exploration, problem-solving. The human works here first.
2. **[design/](design/AGENTS.md)** — Polished design documents produced collaboratively (human + agent).
3. **[adr/](adr/AGENTS.md)** — Immutable Architecture Decision Records. One decision per ADR, timestamped, never updated — only superseded.

### When to use what

- Starting a new feature or major change? Begin in `iteration/`.
- Ready to formalize? Move to `design/` with the agent's help.
- Decision locked in? Record it in `adr/`.
