# pi.nvim

Cursor-style agent integration for Neovim, powered by the
[pi coding agent](https://pi.dev) — embedded as a library, not shelled out to.

A Lua plugin frontend (chat sidebar, inline edit, native diff review) talks to
a TypeScript host we own, which drives pi's SDK (`createAgentSessionRuntime`)
against your existing `~/.pi/agent` config — your auth, models, extensions,
skills, and sessions all carry over.

```
 nvim Lua plugin  ──versioned JSONL stdio──►  host (node, pi SDK)
 (sidebar, input, diff view, keymaps)        (createAgentSessionRuntime)
        ▲                                            │
        └──── pi edits disk → autoread ◄─────────────┘
              + unified patch streams per edit
```

## Status

**Phase 1 (host core done — Lua sidebar next).** The host boots pi's SDK
against the real `~/.pi/agent`, serves protocol commands
(prompt/steer/follow_up/abort/new_session/cycle_thinking), and streams agent
events. Validate with `make smoke` (ADR-003, one near-free prompt).

See [design doc](docs/architecture/design/001-sdk-host-nvim-embedding.md) for
the plan and [ADRs](docs/architecture/adr/) for locked decisions.

## Commands

```bash
make install   # install host deps (CI-safe)
make build     # tsc build of host
make lint      # eslint + prettier + stylua (+ selene if installed)
make test      # vitest
make check     # lint + test + build — run before committing
```

## Documentation

This repo follows the hierarchical `AGENTS.md` doc-set convention (ported from
[pocket](../pocket)). Start at [AGENTS.md](AGENTS.md).
