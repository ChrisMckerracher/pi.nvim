# Authorship
- 2026-07-18 00:55 — agent: pi (k3) (initial standard — Lua counterpart to pocket's python.md, mirrored structure and numbering spirit)
- 2026-07-18 02:40 — agent: pi (k3) (rules 9-10 added after human UX corrections: read-only transcript buffers, visible working affordance)
- 2026-07-18 03:10 — agent: pi (k3) (rule 11 added: virtual lines never wrap — cut-off lesson; panel float pattern noted in rule 9)
- 2026-07-18 05:00 — agent: pi (k3) (rule 12 added: statusline-format escaping — the E542 lesson)
- 2026-08-01 05:40 — agent: pi (k3) (rules 13–18 added from the live-UX hardening session; narrative in [iteration/002](../../architecture/iteration/002-live-ux-hardening.md))

- 2026-09-27 — agent: Codex (visibility toggle contract after keybinding correction)

- 2026-09-27 12:55 — agent: Codex (unnamed buffer identity and guarded editing)

- 2026-09-27 — agent: Codex (native Escape preserves Pi focus)

- 2026-09-27 — agent: Codex (protected panel buffers and visible run controls)

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
9. Display buffers that hold transcripts, logs, or results are read-only: `modifiable = false`, with a `with_modifiable` wrapper for the owning module's own writes. Do not add `readonly` to scratch buffers — it W10-warns on our own writes. Editable buffers exist only where the user is meant to type. Transcript splits remain focusable so users can navigate and copy text; read-only content does not imply a non-focusable window.
10. Every long-running or async operation shows a visible affordance while in flight (spinner, winbar state, or status note) and a clear end state. Silent waiting is a bug.
11. Virtual lines/text (extmarks) never wrap — anything longer than the window is silently cut off. Keep virtual content within the window width (truncate with an ellipsis); long content must be real buffer lines.
12. Winbar and statusline strings are statusline-FORMAT strings, not plain text: a literal `%` (e.g. a context-percent `(34%)`) throws E542 "unbalanced groups". Build the display string, then `:gsub("%%", "%%%%")` before assigning.
13. Declare Lua locals before use — closures capture scope at definition time. A helper defined after its caller is a nil call at runtime (the `format_count` bug).
14. `feedkeys` is a queue, not a call: mode `"n"` defers to typeahead, so a queued `<Esc>` lands in the NEXT dialog or window that opens (it ejected users from snacks.input's insert mode). To exit visual mode synchronously, use mode `"nx"`.
15. `cmdheight=0` hides the DEFAULT `vim.ui.input` and `vim.fn.input` dialogs permanently. Any input prompt must use a floating replacement (snacks.input) — verify input flows after changing cmdline settings.
16. Ensure buffers exist at render funnels. `append_lines`/`append_text` must `ensure_buf()`: features like inline edit fire before the panel has ever opened, and rendering into a nil buffer explodes in a vim.schedule error.
17. Closing a window ≠ deleting a buffer. Sidebars that should disappear from the tabline need an explicit `nvim_buf_delete` on close (neo-tree's buffer otherwise lingers as a phantom tab).
18. Insert-only surfaces type your leader chords. A prompt that is always-in-insert turns `Space e` into the text " e". Give mode-safe twins (Alt+key) and a filetype seam (e.g. `pi_prompt`) so the host config can bind app-level keys there without violating the plugin's boundaries.
19. `:startinsert`/window switches called synchronously from a mapping callback land in the INPUT QUEUE, not in the current state — they apply only when the next keypress drains the queue. Symptom: the first `<leader>a` after Esc-from-prompt "does nothing", the second both applies the queued switch and types itself into the newly focused prompt. Fix: wrap switch+startinsert in `vim.schedule` (runs at the next event-loop pass, immediately and safely). Never fix this by scheduling the ESC-side handler — a stale scheduled callback can fire after the NEXT keypress and revert its work. Specs must await scheduled focus (`vim.wait` on the window), never assert it synchronously. Verified via tmux key-timing repro; headless cannot reproduce it (see testing standards → Interactive Verification).

## Project Layout

- Plugin modules live in `lua/pi_nvim/`; the auto-loaded entry is `plugin/pi_nvim.lua`.
- Tests go in `tests/`, named `*_spec.lua` (plenary busted-style; harness arrives with the first real module).
- No third-party plugin dependencies — native buffers, extmarks, and `jobstart` only (ADR-004, design/001).

20. Window visibility toggles must close an open surface regardless of focus. Keep explicit focus helpers separate; test toggling from the editor as well as from the surface itself.

21. Unnamed normal buffers are valid user code. Identify them by buffer id, never an empty filesystem path. In-memory agent edits must validate changedtick and remain undoable without assigning a filename.

22. Escape in Pi uses native mode transitions and keeps window focus. Do not map it to focus_editor or panel.close. Prompt entry may start insert mode, but users can leave it to navigate and yank; transcript Escape also stays in place. Verify real keystrokes in tmux.

23. Panel-owned split windows must set `winfixbuf` after assigning their buffers. New splits inherit window options: clear protection before assigning a new owned buffer, then restore it. File-tree/picker integrations must route to normal editor windows, never prompt or transcript windows. Keep cancellation controls visible during streaming, not only while idle.
