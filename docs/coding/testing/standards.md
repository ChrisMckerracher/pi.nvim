# Authorship
- 2026-06-19 23:53 — agent: GLM-5.2 (added provenance header; document content predates this standard)
- 2026-07-18 00:45 — agent: pi (k3) (copied from the pocket doc set; adapted from pytest/pytest-cov to vitest + plenary)
- 2026-07-18 01:40 — agent: pi (k3) (rule 4 added: e2e runs share real config state — pi persists thinking level per cwd; reset what you change)
- 2026-07-18 04:30 — agent: pi (k3) (Known Issues section added: plenary directory runs polluted by cross-file leaks; per-file runs are the gate)
- 2026-08-01 05:40 — agent: pi (k3) (headless insert-mode limitation documented; Interactive Verification (tmux) and Environment Facts sections added)
- 2026-08-03 01:15 — agent: pi (k3) (pkill -f self-match caution in Interactive Verification)

# Testing Standards

1. Add unit tests for domain logic and boundary behavior — protocol framing is a boundary and is always tested.
2. Add regression tests for every production bug fix.
3. Keep tests deterministic where possible. Host unit tests never hit the network: use the pi SDK's in-memory factories (`SessionManager.inMemory()`, `SettingsManager.inMemory()`); provider calls are integration tests and must be tagged/skippable.
4. E2E runs against the real `~/.pi/agent` config share its state — pi persists the last-used thinking level per cwd, so a test that cycles thinking changes what the next session restores. Reset what you change before finishing.
4. Diagnose the real cause of a failing test before changing code or tests.
5. Do not weaken contracts or mask failures just to get tests passing.
6. Keep test code to the same clarity and maintainability bar as production code.

## Coverage

- Host: vitest with v8 coverage (`npm test --prefix host`; coverage config arrives with the first domain module beyond protocol framing).
- Lua: plenary busted-style; harness arrives with the first real Lua module (Phase 1). Until then, Lua is covered by stylua/selene via `make lint`.

## Test Organization

- Host tests live in `host/test/`, named `*.test.ts`.
- Lua tests live in `tests/`, named `*_spec.lua`.
- Keep test artifacts (fixtures, data) separate from test logic.

## Known Issues

- **Plenary directory runs are polluted by cross-file window/buffer leaks**
  (one spec's scratch windows change another's geometry). `make test` runs
  each spec FILE in a fresh nvim (`PlenaryBustedFile`) — that is the gate.
  `PlenaryBustedDirectory` exits 1 despite all suites green; specs that touch
  window layout must isolate themselves (`vim.cmd("only")`) regardless.
- **Headless nvim never enters insert mode** (probed: `startinsert` + 500ms
  wait still reports `n`), and floats/pickers render as plain text. Anything
  modal — insert persistence, float visibility, hit-enter prompts, real
  keystroke flows — is UNVERIFIABLE headless.

## Interactive Verification (tmux)

For the headless blind spots above, the harness is a real terminal:

```bash
tmux new-session -d -s verify -x 200 -y 50 -c /path/to/proj "nvim file.py"
tmux send-keys -t verify 'V' 'j' ' ak'      # drive real keystrokes
tmux capture-pane -t verify -p | tail -20  # assert on the visible screen
tmux kill-session -t verify
```

Every interactive bug in the 2026-08-01 hardening session was reproduced in
tmux before fixing. Use it for DAP smoke, dialog flows, and layout checks.

Caution when scripting process cleanup around tmux runs: `pkill -f`
matches its own invoking shell whenever the pattern appears anywhere in
your command string (`pkill -f 'dlv dap'` inside a script whose text
mentions `dlv dap` kills the script itself — the block dies with no
output). Kill by pidfile, or bracket the pattern: `pkill -f '[d]lv dap'`.

## Environment Facts (this machine)

- `python3` exists; **`python` does not** (no alias). DAP `pythonPath`,
  scripts, and shell-outs must call `python3`.
