--- Editor context: capture (selection/file/diagnostics), @file expansion,
--- and message composition. Push model per design/001 — the composed message
--- is built here, client-side, so the host stays a dumb pipe.
local M = {}

---@class PiPendingContext
---@field kind "selection"|"file"
---@field path string
---@field start_line integer|nil
---@field end_line integer|nil
---@field text string
---@field filetype string

---@type PiPendingContext|nil
M.pending = nil

--- cwd-relative when possible (":." falls back to absolute outside cwd).
---@param path string
---@return string
local function relpath(path) return vim.fn.fnamemodify(path, ":.") end

--- Capture the current visual selection into M.pending.
--- Call from a visual-mode mapping; exits visual mode.
function M.capture_visual()
  local mode = vim.fn.mode()
  local start_pos = vim.fn.getpos "v"
  local end_pos = vim.fn.getpos "."
  local bufnr = vim.api.nvim_get_current_buf()

  local start_line, start_col = start_pos[2], start_pos[3]
  local end_line, end_col = end_pos[2], end_pos[3]
  if start_line > end_line or (start_line == end_line and start_col > end_col) then
    start_line, end_line = end_line, start_line
    start_col, end_col = end_col, start_col
  end

  local lines = vim.fn.getline(start_line, end_line)
  if #lines == 0 then
    M.pending = nil
    return
  end
  if mode ~= "V" then
    lines[#lines] = string.sub(lines[#lines], 1, end_col)
    lines[1] = string.sub(lines[1], start_col)
  end

  -- Exit visual mode so the editor returns to a sane state.
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)

  M.pending = {
    kind = "selection",
    path = relpath(vim.api.nvim_buf_get_name(bufnr)),
    start_line = start_line,
    end_line = end_line,
    text = table.concat(lines, "\n"),
    filetype = vim.bo[bufnr].filetype,
  }
end

--- Capture the whole current file into M.pending.
function M.capture_file()
  local bufnr = vim.api.nvim_get_current_buf()
  M.pending = {
    kind = "file",
    path = relpath(vim.api.nvim_buf_get_name(bufnr)),
    start_line = nil,
    end_line = nil,
    text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n"),
    filetype = vim.bo[bufnr].filetype,
  }
end

--- Take the pending context (clears it).
---@return PiPendingContext|nil
function M.consume()
  local pending = M.pending
  M.pending = nil
  return pending
end

--- Compact diagnostics summary: first N errors/warnings for a buffer.
---@param bufnr integer
---@param max_items integer
---@return string|nil
local function diagnostics_summary(bufnr, max_items)
  local diags = vim.diagnostic.get(bufnr, { severity = { max = vim.diagnostic.severity.WARN } })
  if #diags == 0 then return nil end
  local parts = {}
  for i = 1, math.min(#diags, max_items) do
    local d = diags[i]
    local sev = d.severity == vim.diagnostic.severity.ERROR and "E" or "W"
    parts[#parts + 1] = ("%s%d:%d %s"):format(sev, d.lnum + 1, d.col + 1, (d.message:gsub("\n", " ")):sub(1, 120))
  end
  if #diags > max_items then parts[#parts + 1] = ("… +%d more"):format(#diags - max_items) end
  return table.concat(parts, "\n")
end

--- Compact one-block editor state attached to every prompt (push model).
---@return string
function M.editor_state()
  local bufnr = vim.api.nvim_get_current_buf()
  local path = relpath(vim.api.nvim_buf_get_name(bufnr))
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lines = { ("file: %s, line %d"):format(path, cursor[1]) }
  local diags = diagnostics_summary(bufnr, 5)
  if diags then lines[#lines + 1] = "diagnostics:\n" .. diags end
  return "[editor]\n" .. table.concat(lines, "\n")
end

--- Fuller editor state answering the agent-pull `editor_context` tool
--- (ADR-005). Runs in arbitrary contexts — must not fail, must be fast.
---@return string
function M.editor_state_full()
  local bufnr = vim.api.nvim_get_current_buf()
  local path = relpath(vim.api.nvim_buf_get_name(bufnr))
  local cursor = vim.api.nvim_win_get_cursor(0)
  local parts = {
    ("cwd: %s"):format(vim.uv.cwd() or "?"),
    ("current file: %s (line %d, col %d)"):format(path, cursor[1], cursor[2] + 1),
    ("filetype: %s"):format(vim.bo[bufnr].filetype ~= "" and vim.bo[bufnr].filetype or "none"),
  }
  if M.pending then
    local p = M.pending
    parts[#parts + 1] = ("pending selection: %s%s\n```%s\n%s\n```"):format(
      p.path,
      p.start_line and (" lines " .. p.start_line .. "-" .. p.end_line) or "",
      p.filetype,
      p.text
    )
  end
  local diags = diagnostics_summary(bufnr, 10)
  parts[#parts + 1] = "diagnostics:\n" .. (diags or "(none)")
  return table.concat(parts, "\n")
end

--- Expand @path mentions into fenced file blocks appended to the text.
---@param text string
---@param max_lines integer
---@return string expanded_text, string[] expanded_paths
function M.expand_mentions(text, max_lines)
  local expansions = {}
  local paths = {}
  for path in text:gmatch "@([%w%._%~%-%/]+)" do
    local expanded_path = vim.fn.expand(path)
    if vim.fn.filereadable(expanded_path) == 1 then
      local ok, file_lines = pcall(vim.fn.readfile, expanded_path, "", max_lines + 1)
      if ok and #file_lines > 0 then
        local truncated = #file_lines > max_lines
        if truncated then file_lines = vim.list_slice(file_lines, 1, max_lines) end
        local ft = vim.filetype.match { filename = expanded_path } or ""
        expansions[#expansions + 1] = ("[file: %s]%s\n```%s\n%s\n```"):format(
          path,
          truncated and (" (first " .. max_lines .. " lines)") or "",
          ft,
          table.concat(file_lines, "\n")
        )
        paths[#paths + 1] = path
      end
    end
  end
  if #expansions == 0 then return text, paths end
  return text .. "\n\n" .. table.concat(expansions, "\n\n"), paths
end

--- Compose the final wire message: editor state + pending context +
--- @file expansions + the user's text.
---@param user_text string
---@param cfg PiNvimConfig
---@return string message, PiPendingContext|nil attached
function M.compose(user_text, cfg)
  local parts = {}
  local attached = M.consume()

  if cfg.editor_context then parts[#parts + 1] = M.editor_state() end

  if attached then
    if attached.kind == "selection" then
      parts[#parts + 1] = ("[selection from %s, lines %d-%d]\n```%s\n%s\n```"):format(
        attached.path,
        attached.start_line or 0,
        attached.end_line or 0,
        attached.filetype,
        attached.text
      )
    else
      parts[#parts + 1] = ("[file: %s]\n```%s\n%s\n```"):format(attached.path, attached.filetype, attached.text)
    end
  end

  local expanded = M.expand_mentions(user_text, cfg.max_context_file_lines)
  parts[#parts + 1] = expanded
  return table.concat(parts, "\n\n"), attached
end

return M
