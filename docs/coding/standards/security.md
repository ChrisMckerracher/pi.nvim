# Authorship
- 2026-06-19 23:53 — agent: GLM-5.2 (added provenance header; document content predates this standard)
- 2026-07-18 00:45 — agent: pi (k3) (copied from the pocket doc set; Supply Chain section adapted from uv to npm — ignore-scripts/save-exact/cooldown/audit)

# Security Standards

## Supply Chain

This project has explicit supply-chain hardening. Do **not** weaken these settings:

1. `ignore-scripts=true` in `.npmrc` — dependency lifecycle scripts never run (the same hardening pi recommends for its own install).
2. `save-exact=true` in `.npmrc` — exact version pins, no semver ranges. `package-lock.json` is always committed.
3. Dependency cooldown gate — when adding a **new** dependency, install with a date gate so freshly published, unvetted versions are excluded:
   `npm install --save-exact <pkg> --before=$(date -d '7 days ago' +%F)`
   (npm has no rolling config equivalent to uv's `exclude-newer`; the gate is applied at add-time. Pinning the version the human already runs globally — e.g. the pi SDK itself — is inherently exempt: it is vetted by daily use.)
4. `npm audit` runs in CI — vulnerability scanning. Do not ignore findings without justification.
5. Registry is the default npmjs registry only; do not add alternate registries without discussion.

## Coding

1. eslint `strict` config is enabled — fix or explicitly disable findings with a comment explaining why.
2. No secrets, tokens, or credentials in source code or commits. The host must never log auth material from `~/.pi/agent` (ADR-003: the SDK owns credentials; we never touch them).
3. Validate all external input at the boundary (JSONL protocol records, files, env); fail with clear errors.
4. Keep side effects explicit and observable — no hidden state mutations.
