# Authorship
- 2026-07-18 00:45 — agent: pi (k3) (initial version — structure and tables adapted from pocket/AGENTS.md for the Lua+TypeScript toolchain)

# pi.nvim — Agent Instructions

## Project Overview

pi.nvim embeds the **pi coding agent** in Neovim — Cursor-style agent panel,
inline edit, and diff review. Two components:

- **Lua plugin** (`lua/pi_nvim/`) — UI: sidebar, input, diff review, keymaps
- **TypeScript host** (`host/`) — embeds `@earendil-works/pi-coding-agent` via
  SDK; drives `createAgentSessionRuntime()` against the user's `~/.pi/agent`

They communicate over a versioned JSONL stdio protocol
([ADR-002](docs/architecture/adr/002-versioned-jsonl-stdio-protocol.md)).

> **New agent? Start at [docs/HANDOFF.md](docs/HANDOFF.md)** — state of the
> world, deliberately-open work items with next steps, and how to verify
> anything. The rest of this file is the rulebook for working here.

## Project Structure

```
lua/pi_nvim/      # Neovim plugin modules (Lua)
plugin/           # Auto-loaded plugin entry
tests/            # Lua tests (plenary; arrives with first Lua module)
host/             # TypeScript host (Node >=22.19, ESM)
host/src/         # Host source — protocol.ts is the protocol source of truth
host/test/        # vitest tests (unit only, no network)
docs/             # Documentation hierarchy (see below)
Makefile          # build/lint/test/check entry points
```

## Commands

```bash
make install   # npm ci for host (CI-safe)
make build     # tsc build of host
make lint      # eslint + prettier + stylua (+ selene if installed)
make test      # vitest run
make check     # lint + test + build — run before committing
```

## Before You Code

**When in doubt, read the relevant standard before writing code.** These are short — scan them.

| About to… | Read this |
|-----------|-----------|
| Write or modify TypeScript | [typescript.md](docs/coding/standards/typescript.md) |
| Write or modify Lua | [lua.md](docs/coding/standards/lua.md) |
| Change protocol message shapes | [protocol.ts](host/src/protocol.ts) + [ADR-002](docs/architecture/adr/002-versioned-jsonl-stdio-protocol.md) — bump `PROTOCOL_VERSION` |
| Add a new module, split a file, or restructure | [engineering.md](docs/coding/standards/engineering.md) |
| Create a shared helper or extract duplicated code | [engineering.md](docs/coding/standards/engineering.md) — Architecture Rules 6-9 |
| Add a dependency, handle input/auth/secrets | [security.md](docs/coding/standards/security.md) |
| Write or fix tests | [testing/standards.md](docs/coding/testing/standards.md) |
| A test failed and you're about to change code or test to make it pass | Don't — diagnose the real cause first ([testing/standards.md](docs/coding/testing/standards.md)) |
| Start substantial new work | [checklist.md](docs/coding/standards/checklist.md) + design doc in `docs/architecture/design/` first |
| Make an architectural choice others will depend on | Check existing [ADRs](docs/architecture/adr/) first |
| Change behavior, contracts, or public interfaces | [documentation.md](docs/coding/standards/documentation.md) |
| Write a commit message or decide authorship | [commits.md](docs/coding/standards/commits.md) |

…or any other situation of the same spirit: **about to make a structural or domain decision → read the relevant standard first.**

## After You Code

**Leave the codebase smarter than you found it.** When you learn something, capture it.

| Moment | Action |
|--------|--------|
| A sensor (eslint, tsc, vitest, stylua) fires repeatedly on the same pattern | Strengthen the guide — update the relevant standard in `docs/coding/standards/` |
| The human corrects you on a convention or approach | Capture it — add or update a standard |
| You discovered a bug pattern that could recur | Add a regression test + note it in the relevant standard |
| You made an architectural choice others will depend on | Record it — create an ADR in `docs/architecture/adr/` |
| You learned something about the problem domain | Capture it in `docs/product/research/` |
| Behavior, contracts, or public interfaces changed | Update the relevant docs |
| A file grew past ~200 lines or started mixing concerns | Split it per [engineering.md](docs/coding/standards/engineering.md) — Code Quality 1-2 |
| You created a new folder under `docs/` | Add an `AGENTS.md` explaining its purpose and contents |
| You created a new standard document | Link it from the parent folder's `AGENTS.md` index |

…or any other moment of the same spirit: **you learned something that would help you or the next agent avoid a mistake → capture it where the next agent will find it.**

## Documentation Index

| Path | Purpose |
|------|---------|
| `docs/HANDOFF.md` | [Start here — state + open work](docs/HANDOFF.md) |
| `docs/architecture/` | [Architecture decisions, designs, and iteration notes](docs/architecture/AGENTS.md) |
| `docs/coding/` | [Coding standards and testing conventions](docs/coding/AGENTS.md) |
| `docs/product/` | [Product research and domain knowledge](docs/product/AGENTS.md) |
