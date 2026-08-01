# Authorship
- 2026-08-01 05:40 — agent: pi (k3) (initial handoff — state of the world and deliberately-open work)

# Handoff — What To Do Next

**Audience:** future agent or human picking up pi.nvim work.
**State:** v1 shipped and hardened through many live-UX rounds. Repos:
`~/Code/pi.nvim` (plugin + host + doc set) and `~/.config/nvim` (from-scratch
editor config). Everything below is *deliberately* open — not inferred work.

## How to verify anything

```bash
cd ~/Code/pi.nvim
make check      # lint + 17 TS tests + 30+ plenary specs + tsc build
make e2e        # headless full-stack in real nvim (no tokens)
make e2e-live   # ONE real prompt through the host (a few tokens)
make smoke      # boots real ~/.pi/agent via SDK (no tokens)
# Interactive-only behavior (floats, insert mode, real keystrokes):
tmux new-session -d -s x -x 200 -y 50 "nvim file.py"  # send-keys + capture-pane
```

---

## Work item 1 — Debugger: adapter smoke & repair (ide-plan P4)

**Status:** partially investigated 2026-08-01. Adapters launch:
`debugpy-adapter` ✓, `dlv` ✓, `js-debug-adapter` ✓ (all in
`~/.local/share/nvim/mason/bin/`). One real bug found and fixed:
`dap.configurations.python` `pythonPath` fell back to `python`, which does
not exist on this machine (`python3` only) — fixed in `~/.config/nvim/lua/plugins/dap.lua`.

**Still broken:** after that fix, `dap.continue()` never establishes a
session (`require("dap").session()` is nil after the config picker).

**Next steps:**
1. Repro: `cd /tmp/dbgtest && tmux new-session -d -s dbg -x 200 -y 50 -c /tmp/dbgtest "nvim app.py"`, then `4G`, `Space b`, `Space r`, pick "Launch file", inspect.
2. Trace the handshake: `:lua require('dap').set_log_level('TRACE')`, log at `stdpath("cache")/dap.log`. Look for spawn errors vs. initialize failures.
3. Suspects, in order: (a) the snacks picker reappearing suggests `continue()` completes no launch and the next `Space r` re-prompts — confirm what the picker selection actually returned; (b) `pythonPath` value actually reaching the adapter (function refs in config tables are evaluated per launch — verify); (c) debugpy-adapter wrapper wanting its own venv python — compare with invoking it manually; (d) Go/TS need the same smoke after Python passes (`dlv dap`, `js-debug-adapter <port>` manually).
4. Done = breakpoint is hit in tmux repro for **python, then go, then ts**.

## Work item 2 — Hunk-level accept/reject (ADR-004 "future work")

Current: file-level only. Design is largely mechanical:

- **Where:** `lua/pi_nvim/diff.lua` — patch handling already correct
  (prefix-less pi format, mirror reconstruction, `git apply -R`; see ADR-004
  and the round-trip specs).
- **Mechanics:** split a file's combined patch on `^@@ ` boundaries (keep the
  `---`/`+++` headers prepended to each hunk). Reject hunks = `git apply -R`
  of *only the chosen hunks*, applied in reverse document order. Accept
  remains the default no-op.
- **UI:** `Space aD` → file picker → hunk picker (numbered, first changed
  line as label) → reject one at a time; or per-hunk keys inside the diff
  view ( nicer phase 2).
- **Tests:** extend `tests/diff_spec.lua` round-trips with per-hunk cases
  (reject hunk 2 of 3, verify file content matches manually computed result;
  drift case must report, never force).

## Work item 3 — Multi-session panels

Big one — design lives in
[architecture/design/002-multi-session-panels.md](architecture/design/002-multi-session-panels.md).
Decision to build is locked (human, 2026-08-01); protocol/UX approach is
specified there. An ADR should follow once the approach survives contact.

## Also open (decision list, cheaper)

- Dedicated inline-edit session with its own model (Q2 answer, Phase 5)
- Tab autocomplete (ghost text) — separate plugin decision
- Panel image attach (`@img.png` → vision models; host protocol already supports images)
- `cargo install selene` (make lint currently skips it)
- pi `git-checkpoint` extension (ADR-004 deferred)
- `.vscode/launch.json` loader (marked optional)
