# Authorship
- 2026-07-18 00:55 — agent: pi (k3) (initial research capture — feature decomposition that drives design/001 priorities)

# Research: Cursor Feature Landscape → pi.nvim Mapping

Competitive/product analysis: what "feels like Cursor" decomposes into, and
where each capability comes from in our architecture. Informs
[design/001](../../architecture/design/001-sdk-host-nvim-embedding.md).

| Cursor feature | What it does | pi.nvim source | Phase |
|----------------|--------------|----------------|-------|
| Agent panel | Sidebar chat; agent edits files autonomously | Lua sidebar + host SDK session | 1 |
| `@`-mentions | Attach files to the prompt | `@file` completion in input box (host resolves) | 2 |
| Ctrl+K inline edit | Selection + instruction → in-place rewrite | Same warm session; annotated prompt with selection context | 2 |
| Diff review | Changed-files list per turn; accept/reject | Streamed `details.patch` + native nvim diff (ADR-004) | 3 |
| Context awareness | Agent sees current file/selection | Protocol-pushed context block per prompt | 2 |
| Persistent chats | Per-project chat history | `SessionManager.create(cwd)` — shared with CLI | 1 (picker: 4) |
| Model switcher | Pick/cycle model + effort | SDK `set_model`/`cycle_thinking` commands | 1 |
| Tab autocomplete | Ghost-text code completion | **Not pi's domain** — separate plugin, deferred |
| Background agents | Parallel cloud agents | Out of scope v1 (see pocket for the grand version) |

## Insights

1. **The moat is the loop, not the chat.** Cursor's value concentrates in:
   agent edits land → you watch → you review diffs → you accept/reject. Our
   Phase 0–3 sequence front-loads exactly this loop; session pickers and
   status chrome are Phase 4 precisely because they're not the loop.
2. **Accept-by-default is the right default.** Cursor edits are on disk
   immediately; review is retrospective. ADR-004 copies this: accept = no-op,
   reject = reverse patch. Anything stricter (pre-approval) contradicts both
   Cursor's flow and pi's no-permission-popups philosophy.
3. **Warm context beats inline commands.** Ctrl+K works in Cursor because it
   shares the chat's context. A cold `pi -p` one-shot would have been the
   cheap version; the SDK host removes the tradeoff entirely.
4. **Config reuse is a differentiator.** Cursor forked VS Code to own the
   whole stack. We get the same effect by embedding pi's SDK against the
   user's existing `~/.pi/agent` — one config, one session store, two
   frontends (nvim + CLI).
