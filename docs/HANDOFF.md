# Authorship
- 2026-08-01 05:40 — agent: pi (k3) (initial handoff — state of the world and deliberately-open work)
- 2026-08-03 01:15 — agent: pi (k3) (work item 1 closed — debugger verified for python/go/ts; mason venv root cause + cold-go-cache false alarm)

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

## Work item 1 — Debugger: adapter smoke & repair (ide-plan P4) — DONE 2026-08-03

All three adapters verified end-to-end in tmux (breakpoint hit, session
established, clean termination): python (debugpy), go (delve),
js (pwa-node). Fixtures live at /tmp/dbgtest (app.py, main.go, app.js)
— /tmp does not survive reboots; recreate as needed.

**Root cause (python):** the system python upgraded 3.13 → 3.14 after
mason built debugpy's venv. The venv's `bin/python` symlinks
`/usr/bin/python3` (now 3.14), which looks for
`lib/python3.14/site-packages` — debugpy 1.8.16 still sat in
`lib/python3.13`. The adapter exited 1 with `No module named 'debugpy'`
before the DAP handshake. Fixed by rebuilding the venv in place with uv
(`uv venv <pkg>/venv --system-site-packages`, then `uv pip install
--python <pkg>/venv/bin/python debugpy` → 1.8.21). The earlier
`pythonPath` `python` → `python3` config fix was real but secondary;
suspects (a) picker selection and (b) function-valued `pythonPath` were
both fine — config functions are evaluated per launch.

**False alarm (go):** the apparent hang was a cold `go build` cache —
first delve launch compiles std (~10s on this machine). Wait 15–20s
before concluding a hang; adapter and config were fine all along.

**Repro notes:** tmux recipe as before (nvim + `4G`, `Space b`,
`Space r`, Enter). TRACE: `require('dap').set_log_level('TRACE')`, log
at `stdpath("cache")/dap.log` (timestamps UTC). Beware `pkill -f`
self-match when cleaning up adapter processes — see
testing/standards.md → Interactive Verification.

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
