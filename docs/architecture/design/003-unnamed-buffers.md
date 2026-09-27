# Authorship
- 2026-09-27 12:55 — agent: Codex (unnamed buffer editing design)

# Unnamed buffer editing

## Problem and context

Selections from unnamed buffers currently have an empty path, while inline
edit tells the agent to use filesystem tools. There is no file to edit.

## Proposal

Expose unnamed normal buffers through an `editor_buffer` tool over the existing
host-initiated request channel. Context identifies buffers by Neovim buffer id
and changedtick. Read returns their current text; edit replaces one exact unique
text occurrence with a required matching changedtick. Lua owns validation and
mutation, so changes remain unsaved, unnamed, and undoable. Only buffers exposed
through editor context are eligible. Special, saved, deleted, read-only, stale,
and ambiguous targets fail without mutation. Requests expire before late delivery
can mutate a buffer after the host has timed out.

Protocol v3 adds buffer requests and responses. The context broker shares request
correlation and timeout mechanics between context and buffer requests. Inline edit
chooses buffer instructions for unnamed selections and retains file editing for
named files. Chat context can use the same buffer tool.

## Tradeoffs and verification

Disk patch review remains for filesystem edits; unnamed edits use native undo.
No temporary files, implicit save, or dependency changes. Tests cover context,
read/edit round trips, concurrency, exact matching, invalid targets, undo, and
request correlation/timeout. Run `make check` and `make e2e`.

## Open questions

None for this fix. Named unsaved buffers remain a separate concern.
