# Authorship
- 2026-07-18 00:55 — collaborative: Christopher McKerracher + pi (k3) (initial ADR — decision made during architecture interview)

# ADR-002: Versioned LF-Delimited JSONL Protocol over Stdio

## Status

Accepted

## Context

The Lua frontend and the TypeScript host need a channel. Options:

1. **Stdio + JSONL** — the host is spawned by Neovim (`vim.fn.jobstart`), so
   stdin/stdout are free. Same shape as pi's own RPC mode.
2. **Unix socket** — allows reconnects and multiple clients, but adds
   lifecycle and port-management complexity for no current need.
3. **MsgPack-RPC** — Neovim's native RPC. Would let the host act as an nvim
   plugin API peer, but requires a msgpack stack on the Node side and makes
   the boundary harder to inspect.

The framing lesson from pi's RPC docs applies directly: records must be split
on LF (`\n`) **only** — generic line readers that also split on U+2028/U+2029
corrupt JSON payloads containing those characters inside strings.

## Decision

- LF-delimited JSONL on stdio, split on `\n` only; strip one trailing `\r`.
- Commands carry an optional `id`; responses echo it for correlation.
- Events stream host → editor without ids.
- First command is `hello`; the host replies with `PROTOCOL_VERSION`
  (defined in `host/src/protocol.ts`, the protocol source of truth). Version
  mismatch is a hard, visible error via `:checkhealth pi_nvim`.
- One host process per Neovim instance; host exits on `dispose` or stdin EOF.

## Consequences

**Positive:**
- Trivially debuggable: `node host/dist/main.js` in a terminal, type JSON.
- Framing logic is pure and unit-tested (chunk boundaries, CRLF, U+2028).
- Language-agnostic: any future frontend (other editors) can reuse the host.

**Negative:**
- Single-client only (one nvim per host) — acceptable; sessions are on disk
  and shared with the CLI regardless (ADR-003).
- Large binary payloads (images) bloat lines with base64 — acceptable for
  now; revisit if image workflows become central.
