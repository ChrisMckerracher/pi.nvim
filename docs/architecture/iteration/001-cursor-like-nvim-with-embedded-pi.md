# Authorship
- 2026-07-18 00:55 — collaborative: Christopher McKerracher + pi (k3) (interview record — immutable snapshot of the thinking that produced design/001 and ADR-001..004)

# Iteration 001: Cursor-like Neovim with Embedded Pi

Raw record of the architecture interview. Immutable — if thinking evolves,
write a new iteration doc.

## Brief (human)

"I want neovim to feel like cursor with pi embedded in it." Also: "I don't
want a cheap integration. Pi is open source. There should be a way to
literally embed it into the code, not just shell out with `pi -c`. …but in a
way where i still use my configs."

## What pi offers (surveyed from pi docs/README)

- Interactive TUI; print mode (`pi -p`); JSON mode; **RPC mode**
  (`pi --mode rpc`, JSONL stdio for IDEs); **SDK**
  (`createAgentSession` / `createAgentSessionRuntime`, the layer all other
  modes are built on); TypeScript extensions.
- SDK specifics that mattered:
  - `DefaultResourceLoader` does standard discovery of `~/.pi/agent` +
    project resources → user's configs load by default.
  - `SessionManager.create(cwd)` → same on-disk session store as the CLI.
  - `edit`/`write` tools return `details.patch` (unified diff) per call.
  - `session.subscribe(...)` streams every event the TUI sees.

## Interview record

| # | Question | Answer |
|---|----------|--------|
| Q1 | Feature priorities? | Generally agree with agent's decomposition: agent panel, inline edit (Ctrl+K), diff review, context awareness; Tab autocomplete deferred |
| Q2 | Architecture: terminal embed / RPC sidebar / SDK host? | "Pick the most mature architecture… not a cheap integration… literally embed it into the code" → SDK host (ADR-001) |
| Q3 | Inline edit: cold one-shot vs warm session? | Dissolved — SDK host means inline edit uses the same warm session |
| Q4 | Review workflow? | "whatever the sanest way… however cursor does it" → Cursor semantics via streamed patches (ADR-004) |
| Q5 | Context: manual push vs agent pull? | Push via protocol first; agent-pull `editor_context` tool in Phase 4 |
| Q6 | Tab autocomplete in scope? | Deferred (separate plugin, not pi's domain) |
| Q7 | Panel geometry? | Defaults accepted: right split ~40 cols, `<space>a` namespace |
| Q8 | Repo location? | `~/Code/pi.nvim` |
| Q9 | Name? | `pi.nvim`, Lua module `pi_nvim` |
| Q10 | Session behavior? | Fresh session default; resume picker lands by Phase 4 |
| Q11 | Diff-review design? | Delegated to agent (see Q4) |

## Architectural fork considered

```
Option A — terminal embed              Option B — custom SDK host
┌─ nvim ──────────────────────┐        ┌─ nvim ──────────────────────────┐
│ <sp>a ─► :terminal pi (TUI) │        │ chat sidebar  JSONL  OUR host   │
│ <sp>as ─► chansend ctx ─►pi │        │ (Lua plugin) ◄────► (pi SDK lib)│
│ pi edits disk ─► autoread   │        │ stream events, render md in buf │
└─────────────────────────────┘        └─────────────────────────────────┘
 ~50 lines Lua, zero plugins             TS host we own, pinned SDK dep
 pi's TUI, not Cursor's UI               Cursor-grade UX, structured events
```

Middle option (`pi --mode rpc` + Lua sidebar) rejected along with A:
still the CLI as a black box — fixed command surface, no custom tools.

## Notes

- Human cares about mature structure and coding standards → repo adopts the
  pocket doc set (this hierarchy) verbatim where generic, adapted where
  Python-specific.
- Human's nvim config is deliberately agent-friendly already (autoread,
  auto-save, neo-tree watcher) — the integration leans on that instead of
  adding plugins.
