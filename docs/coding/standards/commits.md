# Authorship
- 2026-06-19 23:45 — collaborative: Christopher McKerracher + GLM-5.2 (initial standard: sole/co-author scenarios, trailer format, noreply@pi.local, reasoning-level vocabulary)
- 2026-06-19 23:48 — collaborative: Christopher McKerracher + GLM-5.2 (added agent-identity verification rule — introspect or ask, never infer from context)
- 2026-07-18 00:45 — agent: pi (k3) (copied verbatim from the pocket doc set — standard is harness-generic)

# Commit Authorship Standards

How the pi.nvim agent and the human attribute commits. Git history is an artifact of *who did the work and how*, not just *what changed*. Attribute honestly.

## Three Scenarios

| Scenario | Author | Co-author trailer? |
|----------|--------|--------------------|
| Human coded it alone | Human | No |
| Agent coded it alone | Agent | No |
| Human + agent both contributed | Human | Yes — agent |

There is no "default to co-authored." Pick the row that matches what actually happened.

## What Counts as "Contributed"

- The human wrote or materially edited lines that landed in the commit → co-authored.
- The agent wrote every line and the human only reviewed/typed the commit message → **agent sole author.**
- The human wrote every line and the agent only answered questions, didn't produce committed code → **human sole author.**

Trivia, suggestions that were rejected, or copy-paste transcription by the human do not flip sole → co-authored. Substantive code authorship does.

## Co-Author Trailer Format

When co-authored, add a trailer to the commit body:

```
Fix buffer close quitting neovim

Switch leader-c to mini.bufremove so windows are unshown before
bdelete, preventing the last-window quit.

Co-Authored-By: pi (GLM-4.6, reasoning: high) <noreply@pi.local>
```

The trailer encodes three things the user asked to preserve:

1. **Harness** — `pi`, the coding agent harness the work was done in.
2. **Model** — the specific model used at commit time (e.g. `GLM-4.6`, `claude-sonnet-4.5`, `gpt-5`).
3. **Reasoning level** — the thinking effort in effect, if the model exposes one.

### Determining the Reasoning Level

Pick the value that was actually set for the session/turn:

| Provider | Param | Example values |
|----------|-------|----------------|
| Z.AI (GLM) | `reasoning_effort` | `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max` |
| OpenAI (o-series) | `reasoning_effort` | `minimal`, `low`, `medium`, `high` |
| Anthropic | `thinking.budget_tokens` | `high` / `low` (map to effort terms), or omit the parenthetical |

- If thinking was **off** (no reasoning tokens spent), write `reasoning: off`.
- If the provider/model has no notion of reasoning level, **omit** the parenthetical: `Co-Authored-By: pi (<model>) <...>`.
- Do not invent a level you can't verify. When in doubt, omit it.

### Verifying the Agent's Identity

The agent's **model** is the one field the agent cannot reliably self-report. Models routinely misidentify themselves by copying whatever model name appears in nearby context (docs, chat history, file contents). This is a known failure mode, not a fluke.

Before writing the model into a trailer, the agent **must verify** it through one of:

1. **Programmatic introspection** — query the harness/runtime for the active model. In `pi`, introspect the configured model rather than guessing from memory or surrounding text. This is the preferred path when available.
2. **Human confirmation** — ask the human which model is in use. Use their answer verbatim.

Order matters: try introspection first, fall back to asking. **Never infer the model from context** — a doc mentioning `GLM-4.6` does not mean the running model is `GLM-4.6`.

The same rule applies to reasoning level where possible, though if the harness exposes the live `reasoning_effort` / `budget_tokens` value, that's authoritative.

## Format Rules

1. One `Co-Authored-By:` trailer per agent co-author, on its own line in the commit body.
2. Email is `noreply@pi.local` for the agent — a clearly-fake address that keeps the trailer parseable without claiming a real inbox or a real person.
3. Place trailers after a blank line at the end of the message, separated from prose.
4. The commit's primary `Author:` (git's author field) is always the **human**, even in co-authored or agent-led commits — the human initiated/accepted the work. The trailer records the agent's contribution; it doesn't make the agent the primary author.

## When in Doubt

- Under-attribute rather than over-attribute. If you're unsure whether you "wrote" the code, you probably didn't write it alone — default to co-authored only when there's clear joint work.
- Never add a co-author trailer for a human other than the one committing, without their explicit consent.
