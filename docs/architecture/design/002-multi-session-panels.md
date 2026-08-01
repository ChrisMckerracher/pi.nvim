# Authorship
- 2026-08-01 05:40 — agent: pi (k3) (initial design — handoff doc for the multi-session feature; decision to build locked by human 2026-08-01)

# Design 002: Multi-Session Panels

## Problem

Today the host drives exactly one agent session. Switching sessions replaces
it (`AgentSessionRuntime.switchSession`) — the old session is torn down.
The human wants **parallel sessions**: multiple chats alive at once, each
with its own context, switchable without losing state — potentially visible
side by side.

## Context

- `createAgentSession()` supports any number of concurrent sessions sharing
  one `ModelRuntime`. The constraint is our code, not the SDK.
- `AgentSessionRuntime` is the *switching* layer (new/switch/fork) — it owns
  cwd-bound services per session. Parallel sessions need one runtime per
  session, or direct `createAgentSession` instances with a shared
  `DefaultResourceLoader`/`SettingsManager`.
- Protocol v2 (ADR-002/005) has no session addressing: commands and events
  are implicitly "the" session. The panel renders whatever the host streams.
- Sessions are already files on disk, shared with CLI pi — parallel host
  sessions remain resumable from the terminal.

## Proposal

### Host: session registry + protocol v3

```
AgentHost
  sessions: Map<sessionId, SessionHandle>
  SessionHandle = { session|runtime, subscription, lastActive }
```

- Commands gain optional `sessionId` (default = most recently active) —
  backward compatible with v2 clients.
- Every forwarded event is tagged `sessionId` so the editor can route.
- New commands: `create_session {name?}` (new parallel session, does NOT
  switch), `close_session {sessionId}` (tear down; refuse while streaming),
  existing `list_sessions`/`switch_session` gain an `active` marker.
- One subscription per session at creation; events multiplex onto the same
  stdout channel.

### Editor: session tabs in the panel (recommended), multi-panel later

Option A (recommended first): **one panel, session tabs.** A tab row in the
chat winbar area (or `Space an` cycles): each tab = a live session with full
history (cheap — sessions stay alive in the host, so switching is instant
and lossless). This already delivers "parallel" for the real use case
(work on A, park it, work on B, come back — nothing lost).

Option B (later, if wanted): **multiple panels side by side**, each bound to
a sessionId. Real cost: layout ownership (N right-docked panels vs the
editor), input routing per panel, winbars per session. Only build if A
proves insufficient in practice.

### Phases

1. Host registry + protocol v3 (sessionId addressing, multiplexed events) —
   tests: two sessions, events correctly tagged, close_streaming refused.
2. Panel session tabs + `Space an` new tab + instant switch — tests: switch
   preserves per-session scrollback; tab shows model/thinking per session.
3. (Optional) multi-panel layout.

## Tradeoffs

- Registry + v3 keeps ONE host process per nvim (cheap, single config boot)
  at the cost of protocol churn and per-session bookkeeping. Alternative —
  one host per session — is simpler per host but N config boots, N node
  processes, and breaks the shared session-store ergonomics we get free.
- Tabs-first keeps layout honest (the panel contract stays single-owner of
  the right edge); multi-panel deferred on evidence.

## Open questions

- Do parallel sessions share cwd by default, or can a tab target a different
  project root (per-session runtime services)? Start: shared cwd.
- Cost/tokens in the winbar: per active tab only, or roll-up? Start: active tab.
- Memory: cap on live sessions (evict oldest idle)? Start: no cap, measure.
- CLI interop: identical store already; confirm no lock contention when the
  same session file is open in nvim AND terminal (document as unsupported).
