# Authorship
- 2026-07-18 00:55 — collaborative: Christopher McKerracher + pi (k3) (initial ADR — decision made during architecture interview)

# ADR-001: Embed pi via a Custom TypeScript SDK Host

## Status

Accepted

## Context

Goal: Neovim should feel like Cursor with pi embedded — agent panel, inline
edit, diff review, context awareness. Three integration surfaces were evaluated:

1. **Terminal embed** — run pi's TUI in `:terminal`, drive it with `chansend`.
   Cheap, but we don't own the UI, get no structured events, and multi-line
   paste is fragile. Rejected by the human as "a cheap integration".
2. **`pi --mode rpc` subprocess** — pi's vendor-supported JSONL protocol.
   Real events, but still the CLI as a black box: fixed command surface, no
   custom tools, no programmatic control of sessions/tools.
3. **Custom TypeScript host using the SDK** — depend on
   `@earendil-works/pi-coding-agent` as a pinned npm library and drive
   `createAgentSessionRuntime()`. This is the same layer pi's own interactive,
   print, and RPC modes are built on.

The human's requirement: "Pi is open source. There should be a way to
literally embed it into the code, not just shell out with `pi -c`."

## Decision

Build a TypeScript host (`host/`) that embeds the pi SDK as an exact-pinned
npm dependency. A Neovim Lua plugin frontend talks to it via the protocol in
ADR-002. No `pi` CLI process is ever spawned. The host is effectively a fourth
first-class pi run mode ("NvimMode") alongside interactive/print/RPC.

## Consequences

**Positive:**
- Full control: custom tools (e.g. `editor_context`), every streamed event,
  session replacement APIs, model/thinking control.
- Type safety end to end; the SDK ships its own types.
- We inherit pi's mature session/compaction/retry machinery unchanged.
- Exact pin (`0.80.10`) + lockfile makes upgrades deliberate.

**Negative:**
- We own and maintain the host (new code surface, ~hundreds of lines).
- Users need Node >=22.19 installed (pi itself requires Node anyway).
- SDK API drift on upgrades — mitigated by the pin and by keeping
  SDK-touching code in one module (`host/src/session.ts`).
