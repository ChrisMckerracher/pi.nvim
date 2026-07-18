# Authorship
- 2026-06-19 23:53 — agent: GLM-5.2 (added provenance header; document content predates this standard)
- 2026-07-18 00:45 — agent: pi (k3) (copied from the pocket doc set; contents index adapted: python.md → lua.md + typescript.md)

# Coding Standards

Coding standards for pi.nvim, organized hierarchically. Standards cascade: a parent-level convention flows down to all children unless explicitly overridden.

### Adding a new standard

When you learn something worth codifying:
1. Find the most specific existing subfolder that fits.
2. If none fits, create a new subfolder with its own `AGENTS.md`.
3. Write the standard clearly and concisely.
4. Link it from the parent folder's `AGENTS.md`.

### Contents

| Document | Purpose |
|----------|---------|
| [engineering.md](engineering.md) | Core principles, architecture rules, package layout, code quality |
| [lua.md](lua.md) | Lua/Neovim-specific standards and plugin layout |
| [typescript.md](typescript.md) | TypeScript-specific standards and host layout |
| [security.md](security.md) | Supply chain hardening and secure coding |
| [workflow.md](workflow.md) | Spec-first approach, implementation discipline, change reporting |
| [commits.md](commits.md) | Commit authorship and co-author trailers for human/agent work |
| [documentation.md](documentation.md) | When and how to update docs |
| [checklist.md](checklist.md) | Before/during/after coding checklist |
