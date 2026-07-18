# Authorship
- 2026-06-19 23:53 — agent: GLM-5.2 (added provenance header; document content predates this standard)
- 2026-07-18 00:45 — agent: pi (k3) (copied from the pocket doc set; Package Layout adapted from src/pocket to lua/pi_nvim + host/src; Git gate adapted to `make check`)

# Engineering Standards

## Core Principles

1. Prefer clarity over cleverness.
2. Keep modules small, composable, and single-purpose.
3. Avoid duplication, but do not over-abstract early.
4. Optimize for maintainability and debuggability.
5. Use mature, well-supported libraries before custom equivalents.

## Architecture Rules

1. Keep one clear owner per concern.
2. Keep one source of truth for each policy decision.
3. Keep pipelines explicit and easy to trace end to end.
4. Use concrete types and functions in core domain paths unless multiple real implementations justify abstraction.
5. Remove pass-through components that add no behavior, except approved re-export surfaces that provide a stable public API.
6. Generalize only real shared patterns, not hypothetical ones.
7. When helper concerns are shared across multiple real owners, centralize them instead of duplicating per-package.
8. Prefer decorators or shared helper functions for repeated cross-cutting boundaries — they keep ownership explicit and make behavior easier to audit.
9. When a concern has both shared primitives and domain-owned semantics, keep the shared primitives centralized and the domain semantics in the domain module.
10. When one concrete backing system is chosen, design directly to its native semantics instead of adding backend-agnostic layers.
11. Fail closed for derived state; do not default unknown combinations to success.
12. Record meaningful architecture choices in `docs/architecture/adr/`.

## Package Layout

1. Lua frontend: canonical Neovim plugin layout — modules in `lua/pi_nvim/`, auto-loaded entry in `plugin/`.
2. TypeScript host: source in `host/src/` (NodeNext ESM), tests in `host/test/`.
3. Prefer shallow cohesive modules over large flat directories.
4. When a module owns both interface and implementation code for one cohesive domain, keep them as sibling modules.

## Code Quality

1. One primary responsibility per file.
2. Avoid god files that mix unrelated concerns; split by responsibility.
3. Avoid modules that only re-export other modules unless they provide a stable, intentional public surface.
4. Prefer domain-specific names over generic `do` / `handle` patterns.
5. Keep side effects at the edges, not in core domain logic.
6. Keep canonical domain models at boundaries; avoid duplicate wrapper types unless the external shape truly differs.
7. Name boundary models by domain semantics, not transport direction.

## Git

- Default branch is `main`.
- Commit messages: conventional style (`feat:`, `fix:`, `chore:`).
- Run `make check` before committing.
