# Authorship
- 2026-06-19 23:53 — agent: GLM-5.2 (added provenance header; document content predates this standard)
- 2026-07-18 00:45 — agent: pi (k3) (copied from the pocket doc set; contents index updated)

# Design Documents

Formal design documents for features, systems, or major changes in pi.nvim.

These are produced collaboratively — the human brings iteration thinking, the agent helps flesh out structure, edge cases, and tradeoffs.

Each design doc should cover:
- **Problem**: What are we solving?
- **Context**: Constraints, dependencies, current state
- **Proposal**: The approach, with rationale
- **Tradeoffs**: What we gain and what we give up
- **Open questions**: What's still unresolved

### Contents

| Document | Purpose |
|----------|---------|
| [001-sdk-host-nvim-embedding.md](001-sdk-host-nvim-embedding.md) | Embed pi via SDK host + Lua frontend: architecture, protocol, diff review, phases |
