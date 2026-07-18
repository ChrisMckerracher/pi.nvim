# Authorship
- 2026-07-18 00:55 — collaborative: Christopher McKerracher + pi (k3) (initial ADR — approach delegated to agent: "whatever Cursor does, the sane way")

# ADR-004: Diff Review via SDK-Streamed Patches, No Git Plugin

## Status

Accepted

## Context

Cursor's review loop: the agent edits files directly; the chat panel lists
changed files per turn; the user opens a diff per file and accepts or rejects.
Accept is the default (edits are already on disk); reject restores the file.

Options considered for pi.nvim:

1. **Git plugin** (gitsigns/diffview) — powerful, but the user deliberately
   pruned gitsigns from their config, and it only works in git repos with
   clean-enough baselines.
2. **pi `git-checkpoint` extension** (auto-commit per task) — reviewable
   commits, but pollutes history on WIP branches and requires git discipline
   the agent flow shouldn't impose. Deferred, not rejected.
3. **SDK-streamed patches** — the pi SDK's `edit`/`write` tools return
   `details.patch` (standard unified diff) on every `tool_execution_end`
   event. Every agent edit is already machine-readable at the source.

## Decision

Adopt Cursor semantics built on streamed patches:

- The host collects `details.patch` from every `edit`/`write`
  `tool_execution_end`; per turn it emits a `changes` event: list of
  `{path, patch}`.
- The sidebar shows the changed-files list per turn.
- `<leader>ad` opens a file's change in Neovim's **native diff mode**
  (original reconstructed by reverse-applying the patch to the current file,
  shown in a scratch buffer vs the real buffer).
- **Accept = no-op** (edits already on disk — Cursor's default).
- **Reject = apply the reverse patch** to restore the file. If the file
  changed after the agent edit, fall back to `git checkout` for tracked
  files, else report the conflict and do nothing destructive.
- File-level granularity first (Cursor's default flow); hunk-level
  accept/reject is explicitly future work.
- No git plugin is added to the Neovim config.

## Consequences

**Positive:**
- Exact per-edit fidelity — the patch is what the tool actually applied.
- Zero new Neovim plugin dependencies (honors the user's pruned config).
- Works in non-git directories.

**Negative:**
- Reverse-apply can fail when the file drifted after the edit (editorial
  conflicts become the user's to resolve — reported, never silently forced).
- We must reconstruct "before" buffers correctly for new/deleted files
  (edge cases: create = empty original; overwrite = full-file patch).
- Hunk-level review requires a real merge UI later — accepted as future work.
