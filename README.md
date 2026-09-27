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
`make check` (TS + plenary tests) and `make e2e` (real nvim + real config).
Installable as a regular plugin — see [Installation](#installation).

See [design doc](docs/architecture/design/001-sdk-host-nvim-embedding.md) for
the plan and [ADRs](docs/architecture/adr/) for locked decisions.

## Requirements

| Requirement | Notes |
|-------------|-------|
| Neovim ≥ 0.11 | developed and tested on 0.12 |
| Node.js ≥ 22.19 | host runtime (`host/package.json` engines) |
| [pi](https://pi.dev) configured (`~/.pi/agent`) | the host boots against your pi config — auth, models, extensions, skills live there |
| `rg` (ripgrep) on `$PATH` | pi's search tools use it |

## Installation

The repo ships Lua that loads as-is; the TypeScript host must be compiled
once per checkout (`host/dist/` and `host/node_modules/` are gitignored), so
point your plugin manager's build hook at the two npm commands.

### lazy.nvim

```lua
{
  "ChrisMckerracher/pi.nvim",
  main = "pi_nvim",
  lazy = false,
  build = "npm ci --prefix host && npm run build --prefix host",
  opts = {},
}
```

The build hook runs on install and on every update. For a local checkout
instead of the GitHub remote, use `dir = "~/Code/pi.nvim"` with the same
`build` and `main`.

### Any other manager / manual

Clone the repo anywhere on your runtime path and run the same commands:

```sh
git clone https://github.com/ChrisMckerracher/pi.nvim \
  ~/.local/share/nvim/site/pack/pi/start/pi.nvim
cd ~/.local/share/nvim/site/pack/pi/start/pi.nvim
npm ci --prefix host && npm run build --prefix host
```

Then call setup (lazy does this for you via `opts`):

```lua
require("pi_nvim").setup {}
```

### Verifying

```vim
:checkhealth pi_nvim
```

Checks node version, host build, and SDK presence. Then open any project and
press `<space>a` — the first open boots the host (~5s, once).

## Quickstart

Open any project in Neovim and press `<space>a`. The panel docks to the
right — chat above (read-only, non-focusable), input below. Type, `<CR>`
sends. Attach context with `@path` mentions or send a selection/file
outright; review what the agent changed in a native diff view.

## Keymaps

All defaults live under `<space>a` (`<leader>a`). Set `keymaps = false` in
[configuration](#configuration) to disable them and map the
[`require("pi_nvim")`](lua/pi_nvim/init.lua) API yourself.

### Normal / visual mode

| Key | Mode | Action |
|-----|------|--------|
| `<space>a` | n | Toggle panel (open/close from any window) |
| `<space>as` | v | Send selection to pi |
| `<space>af` | n | Send current file to pi |
| `<space>ak` | v | Inline edit selection with pi |
| `<space>ad` | n | Review agent changes (diff) |
| `<space>aD` | n | Reject agent changes (revert) |
| `<space>an` | n | New session |
| `<space>ar` | n | Resume session (picker includes CLI sessions) |
| `<space>am` | n | Pick model |
| `<space>at` | n | Cycle thinking level |
| `<space>ax` | n | Abort agent run |

### Input window

| Key | Action |
|-----|--------|
| `<CR>` | Send (steers mid-run instead of queueing) |
| `<C-j>` | Newline |
| `@path` | File mention — `<C-x><C-o>` completes paths |
| `<C-d>` / `<C-u>` | Scroll chat |
| `<Esc>` | Back to editor (panel stays open; re-entering the prompt drops you back in insert) |
| `q` | Close panel (normal mode — chat or prompt) |

The panel toggle (`<space>a`, `:Pi`, or `require("pi_nvim").toggle()`) closes an
open panel regardless of focus. While typing a prompt, press Escape to return
to the editor, then `<space>a` to close it. Drafts persist when reopening.

## Commands

| Command | Action |
|---------|--------|
| `:Pi` | Toggle panel |
| `:PiNew` | New session |
| `:PiResume` | Resume session picker |
| `:PiReview` | Review agent changes |
| `:PiAbort` | Abort agent run |

## Configuration

All options go through `setup` (lazy `opts`); they're validated at the
boundary — bad types fail fast with a clear error.

```lua
require("pi_nvim").setup {
  width = 0.35,
  render_thinking = true,
}
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `width` | number | `0.32` | Panel width as a column fraction, clamped [24, 54] |
| `input_height` | number | `6` | Input window height in rows |
| `host_cmd` | string[] | `{ "node", "<plugin>/host/dist/main.js" }` | Host spawn command; override to run a custom host build |
| `auto_scroll` | boolean | `true` | Keep chat pinned to the newest output |
| `render_thinking` | boolean | `false` | `true` streams raw thinking; `false` collapses it to a dim summary line |
| `tool_result_lines` | integer | `12` | Max lines rendered per tool result |
| `max_context_file_lines` | integer | `200` | Max lines per file sent as context |
| `editor_context` | boolean | `true` | Send buffer/selection context with prompts |
| `keymaps` | boolean | `true` | Create the default keymaps |
| `working_messages` | string[] | see `config.lua` | Spinner verbs while the agent works |

## Development

```bash
make install   # install host deps (CI-safe)
make build     # tsc build of host
make lint      # eslint + prettier + stylua (+ selene if installed)
make test      # vitest + plenary specs
make check     # lint + test + build — run before committing
make e2e       # headless full-stack in real nvim (no tokens)
make e2e-live  # one real prompt through the host
```

## Documentation

This repo follows the hierarchical `AGENTS.md` doc-set convention (ported from
[pocket](../pocket)). Start at [AGENTS.md](AGENTS.md) — new agents should read
[docs/HANDOFF.md](docs/HANDOFF.md) first for state and open work.
