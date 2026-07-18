# Authorship
- 2026-07-18 02:10 — agent: pi (k3) (initial ADR — records the protocol extension implemented with Phase 1–4 Lua work)

# ADR-005: Host-Initiated Requests and Client-Side Message Composition

## Status

Accepted

## Context

Two protocol questions surfaced during Lua implementation that ADR-002 did
not cover:

1. **The agent-pull `editor_context` tool inverts the flow.** Normally Neovim
   commands and the host responds. But the tool (running inside the host)
   needs an answer from the *editor* mid-turn: current file, cursor,
   selection, diagnostics. ADR-002 only had nvim→host commands and
   host→nvim events — no way for the host to ask a question and await an
   answer.
2. **Where does message composition live?** Editor context blocks, selection
   fences, and `@file` expansions could be built host-side (protocol carries
   structured context fields) or client-side (Lua composes the final prompt
   text). The design doc sketched host-side injection.

## Decision

1. **Add a host-initiated request/response sub-channel** (protocol v2): the
   host emits `editor_context_request{requestId}` (an event), and Neovim
   answers with an `editor_context_response{requestId, context}` command.
   The host's `EditorContextBroker` correlates by id and times out after 10s
   so a closed/unresponsive editor can never hang the agent.
2. **Message composition is client-side.** Lua composes the complete prompt
   text (editor state + selection/file fences + `@file` expansions + user
   text) and sends it as a plain `prompt`/`steer` message. The host stays a
   dumb pipe for prompting; `prompt` keeps a single `message` field.

## Consequences

**Positive:**
- One mechanism, two directions: the broker pattern generalizes to any
  future host-initiated request (e.g. "open this file", "show this diff").
- The host never hangs on a dead editor — timeouts resolve with an explicit
  "unavailable" string the agent can reason about.
- Client-side composition keeps protocol v2 additive over v1 for prompting
  (no new fields), keeps editor semantics in editor code (engineering rule:
  domain semantics in the domain module), and makes composition unit-testable
  in Lua without a host.
- The timeout and stale-id rules are unit-tested (`context-broker.test.ts`).

**Negative:**
- Response routing now has two modes (command responses by `id`, host
  requests by `requestId`) — a second correlation table to reason about.
  Kept separate deliberately so neither side can confuse them.
- The agent sees prompt text that includes our context blocks verbatim;
  changes to block format are prompt-engineering changes and must be
  evaluated as such (noted in the design doc).
