# Authorship
- 2026-07-18 00:55 — collaborative: Christopher McKerracher + pi (k3) (initial design — polished from [iteration/001](../iteration/001-cursor-like-nvim-with-embedded-pi.md); implements ADR-001..004)
- 2026-07-18 02:10 — agent: pi (k3) (phases 0–4 implemented: protocol v2 (ADR-005), host + Lua plugin shipped; phase table marked done; message composition moved client-side)
- 2026-07-18 03:10 — agent: pi (k3) (chat UI rebuilt after live UX feedback: panel = non-focusable floats, thinking collapsed, fence conceal, spinner; see notes)
- 2026-07-18 03:55 — agent: pi (k3) (final gap closure: token stats in panel title via getSessionStats; @file omni-completion; e2e-live asserts wire contract incl. stats)

# Design 001: SDK Host + Lua Frontend for Neovim Embedding

## Problem

Neovim should feel like Cursor with pi embedded: an agent panel beside the
code, inline edit, reviewable agent changes, and the agent aware of what the
user is looking at — without leaving the editor, and without giving up the
user's existing pi configuration.

## Context

- pi is a TypeScript coding-agent harness. Its interactive TUI, print mode,
  and RPC mode are all thin wrappers over one SDK layer:
  `createAgentSessionRuntime()`. The SDK is published in the same npm package
  (`@earendil-works/pi-coding-agent`, currently `0.80.10`, ESM, Node >=22.19).
- The user's pi config lives at `~/.pi/agent` (auth, settings with default
  model `glm-5.2` + thinking `max`, custom extensions, sessions) and must be
  reused wholesale (ADR-003).
- The user's Neovim config is a deliberately pruned AstroNvim v5 setup that is
  already agent-friendly: `autoread` + `checktime` timer, auto-save on
  idle/focus-loss, neo-tree filesystem watching, format-on-save. New
  third-party Neovim plugins are unwelcome unless they carry their weight.
- Feature landscape and priorities:
  [research/cursor-feature-landscape.md](../../product/research/cursor-feature-landscape.md).
- Locked decisions: [ADR-001](../adr/001-sdk-host-over-cli-embed-or-rpc.md)
  (architecture), [ADR-002](../adr/002-versioned-jsonl-stdio-protocol.md)
  (protocol), [ADR-003](../adr/003-reuse-user-pi-config-and-shared-session-store.md)
  (config reuse), [ADR-004](../adr/004-diff-review-via-streamed-patches.md)
  (diff review).

## Proposal

Two components we own, one versioned boundary:

```
┌─ neovim ────────────────────────┐      ┌─ pi.nvim host (node, OUR code) ──┐
│ lua plugin "pi_nvim"            │      │ TypeScript, ESM, tsc --strict     │
│                                 │      │                                 │
│  ┌───────────┬───────────────┐  │ JSONL│  createAgentSessionRuntime()     │
│  │ neo-tree  │ code buffers  │  │ stdio│   ├─ ModelRuntime (auth.json)    │
│  │           │  (autoread    │◄─┼─────►│   ├─ DefaultResourceLoader       │
│  ├───────────┴───────────────┤  │cmds/ │   │   (~/.pi/agent configs,      │
│  │ chat sidebar │ input box  │  │events│   │    extensions, AGENTS.md)    │
│  │ md stream    │ <cr> send  │  │      │   ├─ SessionManager.create(cwd)  │
│  ├──────────────┴────────────┤  │      │   └─ SettingsManager.create()    │
│  │ diff review (native diff) │  │      │                                 │
│  └───────────────────────────┘  │      │  + custom tools (editor_context)│
│   <space>a… keymaps, statusline │      │  + protocol v1 (versioned)      │
└─────────────────────────────────┘      └─────────────────────────────────┘
         ▲                                              │
         └──────── pi edits disk ─► autoread ───────────┘
              + details.patch streams per edit (ADR-004)
```

### Editor layout

```
┌───────────┬────────────────────────────────┬───────────────┐
│ neo-tree  │        code buffer(s)          │   pi panel    │
│ <space>e  │      Tab / S-Tab cycles        │  <space>a     │
│ files     │   pi edits ─► autoread ─► you  │ chat stream   │
│ refresh   │   watch changes land live      │ @file refs    │
│ live      │                                │ !bash inline  │
├───────────┴────────────────────────────────┴───────────────┤
│ statusline:  lsp • pos • pi: model/session/tokens (phase 4)│
└────────────────────────────────────────────────────────────┘
```

Keymap namespace: `<leader>a…` ("agent"), currently unused in the user's
config. `KEYBINDINGS.md` in the nvim config is updated each phase (which-key
is pruned there, so the markdown cheatsheet is the discoverability story).

### Protocol v1 (sketch; `host/src/protocol.ts` is source of truth)

- **nvim → host:** `hello` · `prompt{message, context?}` · `steer` ·
  `follow_up` · `abort` · `new_session` · `list_sessions` ·
  `switch_session{path}` · `get_state` · `set_model` · `cycle_model` ·
  `cycle_thinking` · `compact` · `dispose`
- **host → nvim:** `hello{protocol, piVersion, model, session}` · `state` ·
  `message_start/update/end` · `tool_execution_start/update/end{…, patch?}` ·
  `turn_start/end` · `agent_start/end/settled` · `queue_update` ·
  `compaction_start/end` · `auto_retry_start/end` · `session_changed` ·
  `error`
- Responses: `{id, success, data|error}`.

### Editor context

Push model: the Lua side attaches context (current file, cursor line, visual
selection, buffer diagnostics) to each `prompt`; the host injects it as a
structured block in the user message. Later (Phase 4): an agent-pull
`editor_context` custom tool wired through protocol request → Lua response.

Inline edit (Ctrl+K analogue): selection + instruction are sent to the **same
warm session** as the panel — there is no cold/warm split in this
architecture.

### Diff review

Per ADR-004: host collects `details.patch` per `edit`/`write`, emits a
per-turn `changes` event; sidebar lists changed files; `<leader>ad` opens
native diff; accept = no-op, reject = reverse patch (git-checkout fallback
for drifted tracked files).

### Phases

| Phase | Deliverable | Verification |
|-------|-------------|--------------|
| 0 ✅ | Repo, standards tooling, protocol v1 types, hello-world host | `make check` green; `node host/dist/main.js` answers `hello` |
| 1 ✅ | Core chat: SDK runtime in host, sidebar streaming render, input box, send/abort, model/thinking/token footer, `<space>a` toggle, `:checkhealth pi_nvim` | `make e2e` green (real nvim + real config) |
| 2 ✅ | Context push, `<space>as` send selection, `<space>ak` inline edit, `@file` expansion | Lua specs green (`make test`) |
| 3 ✅ | Review loop: changes list, native diff, accept/reject per ADR-004, `<space>ad` | diff specs green; reverse-patch mirror safety |
| 4 ✅ | Sessions (picker/new/switch, resume), winbar status, `editor_context` pull tool (ADR-005), docs | `list_sessions` e2e green vs pocket store |

Implementation notes that refine the sketch above:
- Protocol is v2 (ADR-005): adds `list_sessions` / `switch_session` /
  `get_messages` and the host-initiated `editor_context` sub-channel.
- Message composition moved fully client-side (Lua composes context blocks +
  `@file` expansions; `prompt` carries one `message` string).
- Status chrome landed as the chat float's border title (model · thinking ·
  streaming) instead of a statusline component — zero user-config surgery.
- UX revision 1 (live feedback): the chat is a **non-focusable floating
  panel**, not a split — Neovim has no widget primitives, so panel-ness comes
  from `focusable=false` floats + read-only buffers + borders. Thinking
  collapses to a dim summary line (`render_thinking` config expands), code
  fences conceal, an animated spinner shows while the agent runs, and all
  virtual text is width-truncated (virtual lines never wrap).
- Final items: the panel title carries token/context stats (host
  `getSessionStats`, refreshed per settled run), and `@` in the input offers
  path completion via omnifunc (`<C-x><C-o>`). With these, every phase-table
  item is shipped and verified — `make e2e-live` asserts the wire contract
  (events + stats) against a real LLM turn.

Each phase ships working software + tests + `KEYBINDINGS.md` update.

## Tradeoffs

- **We own a Node host.** Cost: a second runtime and a process boundary.
  Benefit: full control and type safety; no terminal scraping; no RPC-mode
  command-surface limits. (Alternatives rejected in ADR-001.)
- **JSONL stdio, single client.** Cost: one nvim per host process.
  Benefit: zero lifecycle complexity; sessions still shared via disk.
  (ADR-002.)
- **Config reuse over isolation.** Cost: host behavior varies with user
  config. Benefit: the human's #1 requirement; identical capabilities to CLI
  pi. (ADR-003.)
- **Patch-based review over git.** Cost: reverse-apply edge cases on drifted
  files. Benefit: zero plugin deps, works outside git, exact fidelity.
  (ADR-004.)
- **Chat UI is ours, not pi's TUI.** Cost: we reimplement rendering,
  queueing affordances, and session pickers that the TUI already has.
  Benefit: the Cursor-grade UX is the entire point of the project.

## Open questions

- Tab autocomplete (Cursor-style ghost text) — deferred; not pi's domain,
  would be a separate plugin decision.
- pi `git-checkpoint` extension for commit-level review — deferred (ADR-004).
- Multi-session / multi-agent panels — out of scope for v1 (sessions are
  switched, not parallel). The user's pocket project explores the grand
  multi-agent version of this space separately.
- Hunk-level accept/reject — future work (ADR-004).
- Lua test harness (plenary) arrives with the first real Lua module in
  Phase 1; until then `make lint` covers Lua via stylua.
