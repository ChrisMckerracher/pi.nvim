# Authorship
- 2026-09-27 12:55 — agent: Codex (buffer editing boundary)

# ADR-006: Edit unnamed buffers through Neovim

## Status

Accepted

## Context

Filesystem tools cannot edit unnamed buffers. Assigning a temporary filename
would change editor semantics and introduce synchronization and cleanup risks.

## Decision

Protocol v3 extends ADR-002/005 with `editor_buffer_request` and
`editor_buffer_response`. The agent's `editor_buffer` tool reads and edits
exposed unnamed normal buffers by id. Neovim validates the target, request expiry,
changedtick, and unique exact text before applying an undoable edit. The existing
context broker owns correlation and timeouts for both request kinds.

## Consequences

Users can discuss and rewrite unsaved snippets without choosing a filename.
Concurrent edits are rejected and the agent must reread. No filesystem artifact
is created. Native undo reverts unnamed edits; streamed disk-patch review remains
specific to named files. Both host and frontend must use protocol v3.
