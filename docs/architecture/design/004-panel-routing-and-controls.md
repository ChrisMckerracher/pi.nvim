# Authorship
- 2026-09-27 — agent: Codex (file routing and discoverable panel controls)

# Panel routing and controls

## Problem

File-tree opens can replace Pi's prompt window with a file, while shortcuts for
navigation, cancellation, and session management are difficult to discover.

## Proposal

Pi marks its transcript and prompt windows `winfixbuf` after assigning their
owned buffers. New panel splits explicitly clear inherited protection before
assigning buffers. Neo-tree excludes Pi and other sidebar/special buffers from
file destinations. The editor config routes file pickers and buffer navigation
to an ordinary editor window, creating one if necessary.

The editor config adds `Space w h/j/k/l` and direct editor/tree/Pi destinations.
Pi keeps a visible `Ctrl-C stop` / `F2 sessions` hint even while streaming.
Panel-local Ctrl-C cancels the run in normal and insert mode without erasing a
draft. F2 opens a native selection menu for new/resume sessions, also exposed as
`:PiSessions`. New sessions clear prior chat only after a successful response.

## Tradeoffs

Direct buffer replacement commands issued inside Pi fail visibly rather than
corrupting its layout. Editor file commands route to a code window. Existing
Escape behavior, toggle semantics, and newline keys remain intact. No new
plugins or protocol changes are needed.

## Validation

Regression tests cover window protection, split reopening, control mappings,
abort responses, and session menu dispatch. Verify actual Neo-tree opens,
normal/insert navigation, cancellation and session menus in a terminal using
the installed config. Run `make check` before publishing.
