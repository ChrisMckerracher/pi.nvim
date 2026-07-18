# Authorship
- 2026-06-02 — human: Christopher McKerracher (initial draft — structure and content rules)
- 2026-06-02 — agent: Claude (added provenance standard with immutability rule for iteration docs, multi-line revision trail for living docs)
- 2026-07-18 00:45 — agent: pi (k3) (copied verbatim from the pocket doc set — standard is harness-generic)

# Documentation Standards

## Structure

1. Standards are composable and hierarchical — the same rules apply to docs as to code.
2. A large, dense documentation file is a code smell. Split it when it covers multiple concerns. Each document should have one clear topic.
3. When a folder's `AGENTS.md` or a standards file grows beyond ~50 lines of content, consider splitting into focused sub-documents.
4. Use `AGENTS.md` files as folder indexes — purpose, links to contents, no more.

## Provenance

Every document under `docs/` must begin with a provenance header stating author, timestamp, and authorship type.

**Format:**

```markdown
# Authorship
- YYYY-MM-DD HH:MM — <type>: <name> (<summary of change>)
```

- **Timestamp** — ISO 8601 date and time.
- **Type** — `human`, `agent`, or `collaborative`.
- **Name** — person or agent identifier.
- **Summary** — brief description of what was written or changed.

### Iteration docs (`docs/architecture/iteration/`)

Iteration docs are **immutable snapshots of thinking**. They carry a single provenance entry. Never modify an iteration doc after creation — if thinking evolves, write a new iteration doc.

```markdown
# Authorship
- 2026-06-02 14:30 — human: Christopher McKerracher (initial exploration of agent abstraction)
```

### Living docs (standards, ADRs, design docs)

Living docs carry a **multi-line revision trail**. Each substantive change gets a new line appended. The doc itself is the current truth; the revision trail shows how it got there.

```markdown
# Authorship
- 2026-06-02 14:30 — human: Christopher McKerracher (initial draft)
- 2026-06-02 16:10 — agent: Claude (added provenance rule)
- 2026-06-03 09:00 — human: Christopher McKerracher (revised immutability rule for iteration docs)
```

## Content

1. Update docs when behavior or contracts change.
2. Keep examples executable and current.
3. Prefer positive responsibility statements; avoid "what this does not do" sections unless needed to prevent a boundary mistake.
4. Avoid historical rename notes in active docs; use current canonical names only.
5. When you change something runnable, include copy-paste repo commands so the change can be verified locally.
6. Keep unresolved questions in `docs/architecture/iteration/` while exploring; move answers into design docs or ADRs once resolved.
7. Capture conventions that reduce future human-AI correction loops — this is the compound engineering discipline.
