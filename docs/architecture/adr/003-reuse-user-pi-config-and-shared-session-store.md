# Authorship
- 2026-07-18 00:55 — collaborative: Christopher McKerracher + pi (k3) (initial ADR — human requirement: "in a way where I still use my configs")

# ADR-003: Reuse the User's `~/.pi/agent` Config and Session Store

## Status

Accepted

## Context

The human already runs CLI pi with a real configuration at `~/.pi/agent`:
`auth.json` (provider credentials), `settings.json` (default model `glm-5.2`,
thinking level `max`), `models.json`, global extensions (`web-search.ts`,
`fetch-url.ts`, a custom provider extension), and a session store organized by
working directory. The human's explicit requirement: the embedded integration
must keep using these configs — no parallel setup, no copied credentials.

The pi SDK's defaults are built for exactly this: `DefaultResourceLoader`
performs standard discovery against `agentDir` (default `~/.pi/agent`) and the
working directory; `ModelRuntime.create()` resolves auth from `auth.json` and
env; `SettingsManager.create()` merges global + project `settings.json`;
`SessionManager.create(cwd)` persists to the same store the CLI uses.

## Decision

The host uses SDK defaults throughout — no custom `agentDir`, no config
copying, no credential handling of our own:

- `DefaultResourceLoader` — extensions, skills, prompts, themes, AGENTS.md
- `ModelRuntime.create()` — auth + model catalog
- `SettingsManager.create()` — user settings (model, thinking level, …)
- `SessionManager.create(cwd)` — sessions shared with the CLI on disk

## Consequences

**Positive:**
- The embed boots with the user's auth, default model, thinking level,
  extensions, skills, and AGENTS.md — identical capabilities to CLI pi.
- Sessions are shared: start a chat in Neovim, continue it with `pi -c` in a
  terminal (and vice versa). One history, two frontends.
- Zero secret material in this repo or our logs (see security standard).

**Negative:**
- Host behavior legitimately varies with user config — mitigated by surfacing
  loaded resources in `:checkhealth pi_nvim` (Phase 1).
- Project-local `.pi/` resources follow pi's trust semantics: untrusted
  projects are ignored in non-interactive operation until the user runs
  `/trust` in CLI pi. Documented in the README; no workaround implemented.
- User extensions must be RPC/embed-compatible; TUI-only extension UI
  (`ctx.ui.custom()`) is unavailable outside the TUI — surfaced as host
  errors rather than silently degraded where detectable.
