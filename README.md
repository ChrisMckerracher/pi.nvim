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

**Phases 0–4 implemented (v1).** The host boots pi's SDK against the real
`~/.pi/agent`; the Neovim plugin provides the chat sidebar, context push,
inline edit, patch-based diff review, and session resume — verified by
`make check` (13 TS + 14 Lua tests) and `make e2e` (real nvim + real config).
Install into Neovim with a lazy.nvim `dir` spec (see below).

```lua
{ "pi.nvim", dir = "~/Code/pi.nvim", main = "pi_nvim", lazy = false,
  build = "make build", opts = {} }
```

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
