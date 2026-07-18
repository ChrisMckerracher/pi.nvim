# Authorship
- 2026-06-19 23:53 — agent: GLM-5.2 (added provenance header; document content predates this standard)
- 2026-07-18 00:45 — agent: pi (k3) (copied verbatim from the pocket doc set — paths are toolchain-agnostic)

# Workflow Standards

## Spec-First

1. Start substantial work with a spec-first approach: write or tighten the design doc in `docs/architecture/design/` before implementing.
2. Default to spec-first unless the change is truly tiny and doesn't justify a design doc.
3. After agreeing on an architecture direction, check whether it warrants an ADR in `docs/architecture/adr/` before decomposing into implementation.

## During Implementation

1. Diagnose the real cause of a failing test before changing code or tests; do not brute-force them into passing.
2. Keep changes aligned with the active design doc.
3. Keep the design doc aligned with behavior changes.
4. When you change something runnable, include copy-paste verification commands in your response.

## Change Reporting

1. Keep responses direct and concrete about tradeoffs, risks, and sequencing.
2. Challenge weak assumptions with explicit alternatives.
3. Propose defaults when ambiguity exists — keep momentum.
4. Prefer clear maintainable code over patchy quick fixes.
