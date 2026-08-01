# Authorship
- 2026-08-01 05:40 — agent: pi (k3) (immutable session narrative — how v1's UX hardened; lessons referenced by lua.md rules 13–18 and testing standards)

# Iteration 002: Live-UX Hardening (session narrative)

Immutable snapshot of what live use taught after v1 shipped. If thinking
evolves, write a new iteration doc.

## The arc

1. **"Feels bolted on."** The chat lived in floats: non-focusable, overlay,
   resize-proof. The user compared it to neo-tree, which "feels part of
   neovim". Realization: panel-ness comes from **content** (read-only
   transcript), not **geometry**. Floats were a detour; **native splits**
   gave sibling resize, native scroll, native wheel, winbar titles — and
   deleted a whole layer of shift/restore machinery.

2. **The insert-only paradox.** Making the prompt a true text field
   (insert always) broke every leader key inside it — `Space e` typed a
   literal " e". The user reported "Space e does nothing, Esc opens it":
   Esc returned them to normal mode, and their *retry* worked. Fix was not
   one thing but a seam: Alt-twins (`M-e/a/v/d/q`) bound via a `pi_prompt`
   filetype so app config owns app keys there.

3. **The bug chain** (each surfaced by the previous fix):
   - `chat.echo_user` → `append_lines` on a nil buffer (inline edit fires
     before first panel open) → ensure-at-funnel rule.
   - `format_count` called before its local was declared →
     declare-before-use rule.
   - `(6%)` in a winbar → statusline-format strings need `%%` (rule 12).
   - `capture_visual` queued an Esc that landed *inside the next dialog*,
     ejecting users from snacks.input's insert mode → synchronous `nx` rule.
   - `cmdheight=0` hid the default `vim.ui.input` entirely → floating
     input replacement rule.
   - Closing the tree left its buffer in the tabline → close ≠ wipe rule.

4. **The verification breakthrough:** tmux. Floats, insert mode, hit-enter,
   and real keystroke flows are all invisible to headless nvim — but
   `tmux new-session -d ... "nvim"` + `send-keys` + `capture-pane` is a real
   terminal. Every "big bug when I hit enter" class of issue since has been
   reproduced in tmux first, fixed second.

5. **Convergence.** Navigation unified on one 3-state contract
   (closed → open+focus · outside → focus · inside → close) driven by one
   shared `sidebar.lua`, plus `Space q` close-all. Special cases
   (focus-switch, custom scroll keys, wheel routing) were deleted, not
   refined — "simplest keybinds win".

## Meta-lessons for agents working here

- Atomic edit failures roll back silently — after a failed multi-part edit,
  VERIFY the file before assuming. (A toggle rewrite vanished this way and
  was only caught by a trace spec.)
- stylua reformats files under you; exact-match edits drift. Match against
  the current file, never memory.
- Headless can prove logic (protocol, geometry, parsing); only tmux proves
  interaction. Budget both.
