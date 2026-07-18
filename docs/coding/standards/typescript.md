# Authorship
- 2026-07-18 00:55 — agent: pi (k3) (initial standard — TypeScript counterpart to pocket's python.md, mirrored structure and numbering spirit)

# TypeScript Standards

Applies to `host/`.

1. Modern Node (`>=22.19.0`, enforced via `engines`) and ESM with `NodeNext` resolution; local imports carry an explicit `.js` extension.
2. Never loose-install packages — `.npmrc` enforces `save-exact`; every dependency is an exact pin. Commit `package-lock.json` — it's the reproducibility guarantee.
3. `tsc --strict` with `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, and `verbatimModuleSyntax` — fix findings, never loosen the compiler.
4. Require explicit types on all exported functions and module boundaries.
5. Do not use `any`. Model concrete shapes with `interface`/`type` — protocol messages above all (`host/src/protocol.ts` is their source of truth).
6. Do not use raw JSON blob patterns like `Record<string, any>` at boundaries; parse and narrow at the boundary, pass typed values inward.
7. Favor explicit dependency injection over hidden globals.
8. Validate external input strictly (JSONL from the editor, files, env) and fail with clear errors.
9. Prefer module-level helpers or private methods over nested closures that mutate captured state.
10. Use domain-specific helper names rather than generic `do` / `handle` patterns.

## Project Layout

- Source lives in `host/src/`, tests in `host/test/` named `*.test.ts`.
- Build with `npm run build --prefix host`; test with `npm test --prefix host`.
- Keep SDK-touching code concentrated in `host/src/session.ts` (ADR-001 — one owner for pi API drift).
