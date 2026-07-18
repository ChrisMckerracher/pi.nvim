# Authorship
- 2026-07-18 00:55 — agent: pi (k3) (initial standard — Lua counterpart to pocket's python.md, mirrored structure and numbering spirit)
- 2026-07-18 02:40 — agent: pi (k3) (rules 9-10 added after human UX corrections: read-only transcript buffers, visible working affordance)

# Lua Standards

Applies to `lua/`, `plugin/`, `tests/`.

1. Neovim Lua (LuaJIT 5.1 semantics); target Neovim 0.11+ APIs (`vim.uv`, `vim.system`, `vim.api`, `vim.fn.jobstart`).
2. Format with stylua — 120 col, 2-space indent, double quotes (`.stylua.toml` at repo root). Lint with selene when installed (`selene.toml` at repo root).
3. EmmyLua annotations (`---@class`, `---@param`, `---@return`) on all public functions and module tables — lua_ls is the language server and is part of the user's config.
4. One primary responsibility per module; modules return a table and never set globals.
5. Validate all config and external input at the `setup()` / command boundary; report misuse with `vim.notify(msg, vim.log.levels.ERROR)`, never silently ignore.
6. Keep side effects (job control, buffer/window mutation) in dedicated owner modules — `host.lua` owns the job process, `chat.lua` owns sidebar buffers — not scattered through domain logic.
7. Never mutate UI state directly from a job callback's fast event context; route through `vim.schedule`.
8. Use domain-specific helper names rather than generic `do` / `handle` patterns.
9. Display buffers that hold transcripts, logs, or results are read-only: `modifiable = false`, with a `with_modifiable` wrapper for the owning module's own writes. Do not add `readonly` to scratch buffers — it W10-warns on our own writes. Editable buffers exist only where the user is meant to type.
10. Every long-running or async operation shows a visible affordance while in flight (spinner, winbar state, or status note) and a clear end state. Silent waiting is a bug.

## Project Layout

- Plugin modules live in `lua/pi_nvim/`; the auto-loaded entry is `plugin/pi_nvim.lua`.
- Tests go in `tests/`, named `*_spec.lua` (plenary busted-style; harness arrives with the first real module).
- No third-party plugin dependencies — native buffers, extmarks, and `jobstart` only (ADR-004, design/001).
