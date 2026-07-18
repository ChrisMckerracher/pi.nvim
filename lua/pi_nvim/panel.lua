--- Panel layout: the agent surface as floating windows, NOT editor splits.
--- Neovim has no widget primitives — everything is a buffer in a window —
--- so the panel feel comes from three properties: the chat float is
--- non-focusable (the cursor cannot enter it), its buffer is read-only
--- (chat.lua), and both floats render with panel borders. The input float
--- is the only focusable element. Owns geometry, titles, scroll plumbing.
local chat = require "pi_nvim.chat"
local input = require "pi_nvim.input"

local M = {
  ---@type integer|nil
  chat_win = nil,
  ---@type integer|nil
  input_win = nil,
  ---@type PiNvimConfig|nil
  _cfg = nil,
  ---@type integer|nil
  _resize_group = nil,
  _last_state = { model = nil, thinkingLevel = "?", isStreaming = false },
}

---@param cfg PiNvimConfig
function M.setup(cfg)
  M._cfg = cfg
  M._resize_group = vim.api.nvim_create_augroup("PiNvimPanelResize", { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = M._resize_group,
    callback = function() M._relayout() end,
  })
end

---@return boolean
function M.is_open()
  return (M.chat_win ~= nil and vim.api.nvim_win_is_valid(M.chat_win))
    or (M.input_win ~= nil and vim.api.nvim_win_is_valid(M.input_win))
end

--- Panel width capped so the editor always keeps at least half the screen.
---@return integer
--- Panel width in columns (fraction or absolute, clamped — config.lua).
---@return integer
local function panel_width() return require("pi_nvim.config").resolve_width(M._cfg) end

---@return integer chat_text_height, integer chat_row, integer input_row
local function layout_rows()
  local cfg = M._cfg
  -- Full editor height: chat outer + input outer == vim.o.lines exactly.
  local input_outer = cfg.input_height + 2
  local chat_outer = math.max(4, vim.o.lines - input_outer)
  return chat_outer - 2, 0, chat_outer
end

---@param width integer
---@param height integer
---@param row integer
---@param focusable boolean
---@param title string
---@return vim.api.keyset.win_config
local function float_config(width, height, row, focusable, title)
  return {
    relative = "editor",
    anchor = "NE",
    row = row,
    col = vim.o.columns,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    focusable = focusable,
    noautocmd = true,
    title = title,
    title_pos = "left",
  }
end

---@param n integer
---@return string
local function format_count(n)
  if n >= 1000 then return ("%.1fk"):format(n / 1000) end
  return tostring(n)
end

---@return string
local function chat_title()
  local state = M._last_state
  local model = state.model and state.model.id or "no-model"
  local streaming = state.isStreaming and " · …" or ""
  local tokens = ""
  if state.stats and state.stats.totalTokens > 0 then
    tokens = (" · %s tok"):format(format_count(state.stats.totalTokens))
    if state.stats.contextPercent then tokens = tokens .. (" (%d%%)"):format(state.stats.contextPercent) end
  end
  return (" pi · %s · %s%s%s "):format(model, tostring(state.thinkingLevel), streaming, tokens)
end

--- Open the panel (focuses the input float; no-op if already open).
function M.open()
  if M.is_open() then
    M.focus_input()
    return
  end
  local cfg = M._cfg
  local width = panel_width()
  local chat_height, chat_row, input_row = layout_rows()

  M.chat_win =
    vim.api.nvim_open_win(chat.ensure_buf(), false, float_config(width, chat_height, chat_row, false, chat_title()))
  vim.wo[M.chat_win].wrap = true
  vim.wo[M.chat_win].linebreak = true
  vim.wo[M.chat_win].breakindent = true
  vim.wo[M.chat_win].conceallevel = 2
  vim.wo[M.chat_win].concealcursor = "nvic"

  M.input_win = vim.api.nvim_open_win(
    input.ensure_buf(),
    true,
    float_config(width, cfg.input_height, input_row, true, " message pi — <CR> send · <C-j> nl · <C-d/u> scroll ")
  )
  vim.wo[M.input_win].wrap = true
  vim.wo[M.input_win].linebreak = true

  vim.cmd "startinsert"
end

--- Close both floats; buffers persist for the next open.
function M.close()
  if M.chat_win and vim.api.nvim_win_is_valid(M.chat_win) then vim.api.nvim_win_close(M.chat_win, true) end
  if M.input_win and vim.api.nvim_win_is_valid(M.input_win) then vim.api.nvim_win_close(M.input_win, true) end
  M.chat_win, M.input_win = nil, nil
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

function M.focus_input()
  if M.input_win and vim.api.nvim_win_is_valid(M.input_win) then
    vim.api.nvim_set_current_win(M.input_win)
    vim.cmd "startinsert"
  end
end

--- Recompute geometry (editor resized, title state changed).
function M._relayout()
  if not M.is_open() then return end
  local width = panel_width()
  local chat_height, chat_row, input_row = layout_rows()
  -- noautocmd is an open-time-only option; set_config rejects it.
  local chat_cfg = float_config(width, chat_height, chat_row, false, chat_title())
  chat_cfg.noautocmd = nil
  local input_cfg = float_config(
    width,
    M._cfg.input_height,
    input_row,
    true,
    " message pi — <CR> send · <C-j> nl · <C-d/u> scroll "
  )
  input_cfg.noautocmd = nil
  if M.chat_win and vim.api.nvim_win_is_valid(M.chat_win) then vim.api.nvim_win_set_config(M.chat_win, chat_cfg) end
  if M.input_win and vim.api.nvim_win_is_valid(M.input_win) then vim.api.nvim_win_set_config(M.input_win, input_cfg) end
end

--- Reflect host state in the chat float title (model · thinking · streaming).
---@param state PiHostState
function M.update_winbar(state)
  M._last_state = state
  M._relayout()
end

--- Scroll the chat panel without focusing it (bound to <C-d>/<C-u> in input).
---@param direction integer 1 = down half page, -1 = up half page
function M.scroll_chat(direction)
  if not (M.chat_win and vim.api.nvim_win_is_valid(M.chat_win)) then return end
  local keys = direction > 0 and "\x04" or "\x15"
  vim.api.nvim_win_call(M.chat_win, function() vim.cmd("normal! " .. keys) end)
end

--- Scroll the chat panel by N lines (mouse wheel path).
---@param lines integer positive = down, negative = up
function M.scroll_chat_lines(lines)
  if not (M.chat_win and vim.api.nvim_win_is_valid(M.chat_win)) then return end
  local key = lines > 0 and "\x05" or "\x19" -- <C-e> / <C-y>
  vim.api.nvim_win_call(M.chat_win, function() vim.cmd(("normal! %d%s"):format(math.abs(lines), key)) end)
end

--- Jump the chat panel to an edge (gg / G semantics, without focus).
---@param edge "top"|"bottom"
function M.scroll_chat_edge(edge)
  if not (M.chat_win and vim.api.nvim_win_is_valid(M.chat_win)) then return end
  vim.api.nvim_win_call(M.chat_win, function() vim.cmd("normal! " .. (edge == "top" and "gg" or "G")) end)
end

return M
