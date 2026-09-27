--- Panel layout: the agent surface as ordinary split windows docked right —
--- the same grid neo-tree uses, so the panel resizes, reflows, and shares
--- separators like a native part of the editor (not a float bolted on top).
--- Panel-ness (not an edit field) comes from content, not geometry: the chat
--- buffer is read-only (chat.lua) and the prompt below is the only insert
--- surface. Keys typed in the chat viewer bounce to the prompt.
local chat = require "pi_nvim.chat"
local input = require "pi_nvim.input"

local M = {
  ---@type integer|nil
  chat_win = nil,
  ---@type integer|nil
  input_win = nil,
  ---@type PiNvimConfig|nil
  _cfg = nil,
  _last_state = { model = nil, thinkingLevel = "?", isStreaming = false },
  ---@type integer|nil runtime width override from resize gestures
  _width_override = nil,
  ---@type integer|nil runtime input-height override from resize gestures
  _input_height_override = nil,
  ---@type integer|nil editor window the panel was opened from
  _last_editor_win = nil,
  ---@type integer|nil spinner animation timer
  _spinner_timer = nil,
}

---@param cfg PiNvimConfig
function M.setup(cfg)
  M._cfg = cfg
  math.randomseed(os.time())
end

---@return boolean
function M.is_open()
  return (M.chat_win ~= nil and vim.api.nvim_win_is_valid(M.chat_win))
    or (M.input_win ~= nil and vim.api.nvim_win_is_valid(M.input_win))
end

---@return integer
local function current_width() return M._width_override or require("pi_nvim.config").resolve_width(M._cfg) end

---@return integer
local function input_height() return M._input_height_override or M._cfg.input_height end

---@param n integer
---@return string
local function format_count(n)
  if n >= 1000 then return ("%.1fk"):format(n / 1000) end
  return tostring(n)
end

---@return string
local function input_title() return " send <CR> · newline <C-j> · scroll <PgUp/Dn> " end

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
  -- Winbars are statusline-format strings: literal % must be escaped.
  return ((" pi · %s · %s%s%s "):format(model, tostring(state.thinkingLevel), streaming, tokens):gsub("%%", "%%%%"))
end

--- Window dressing shared by both panel windows.
---@param win integer
local function dress_window(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].winfixwidth = true
end

--- Open the panel: full-height split docked right (like neo-tree), prompt in
--- a short split below the chat. Focuses the prompt.
function M.open()
  if M.is_open() then
    M.focus_input()
    return
  end
  local cur = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_config(cur).relative == "" then M._last_editor_win = cur end

  vim.cmd "botright vsplit"
  M.chat_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(M.chat_win, current_width())
  vim.api.nvim_win_set_buf(M.chat_win, chat.ensure_buf())
  dress_window(M.chat_win)
  vim.wo[M.chat_win].breakindent = true
  vim.wo[M.chat_win].conceallevel = 2
  vim.wo[M.chat_win].concealcursor = "nvic"
  vim.wo[M.chat_win].winbar = chat_title()

  vim.cmd "belowright split"
  M.input_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(M.input_win, input_height())
  vim.api.nvim_win_set_buf(M.input_win, input.ensure_buf())
  dress_window(M.input_win)
  vim.wo[M.input_win].winfixheight = true
  vim.wo[M.input_win].winbar = input_title()

  -- The chat is a viewer: native Escape keeps focus here, q closes the panel,
  -- typing bounces to the prompt.
  local chat_buf = vim.api.nvim_win_get_buf(M.chat_win)
  vim.keymap.set("n", "q", M.close, { buffer = chat_buf, desc = "Close pi panel" })
  for _, key in ipairs { "i", "a", "o", "O", "<CR>" } do
    vim.keymap.set("n", key, M.focus_input, { buffer = chat_buf, desc = "Go to pi prompt" })
  end

  -- Scheduled like focus_input: open() runs inside the <leader>a mapping;
  -- a synchronous startinsert from there sits in the input queue (applied
  -- at the next keypress, in whatever window then holds focus).
  vim.schedule(function() vim.cmd "startinsert" end)
end

--- Close both windows; buffers persist for the next open.
function M.close()
  M.stop_spinner()
  if M.chat_win and vim.api.nvim_win_is_valid(M.chat_win) then vim.api.nvim_win_close(M.chat_win, true) end
  if M.input_win and vim.api.nvim_win_is_valid(M.input_win) then vim.api.nvim_win_close(M.input_win, true) end
  M.chat_win, M.input_win = nil, nil
end

--- Toggle visibility regardless of which window currently has focus.
function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

function M.focus_input()
  if M.input_win and vim.api.nvim_win_is_valid(M.input_win) then
    -- Scheduled: switch+startinsert called synchronously from a mapping
    -- (e.g. <leader>a refocus) lands in the INPUT QUEUE and does not apply
    -- until the next keypress drains it — the user sees "nothing happened",
    -- and the following key both triggers the queued switch and then lands
    -- in the prompt as text. A scheduled callback runs at the next event
    -- loop pass instead, immediately and safely.
    vim.schedule(function()
      vim.api.nvim_set_current_win(M.input_win)
      vim.cmd "startinsert"
    end)
  end
end

--- Focus the editor window the panel was opened from (or any normal window).
function M.focus_editor()
  if M._last_editor_win and vim.api.nvim_win_is_valid(M._last_editor_win) then
    vim.api.nvim_set_current_win(M._last_editor_win)
    return
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == "" then
      vim.api.nvim_set_current_win(win)
      return
    end
  end
end

-- ---------------------------------------------------------------------------
-- Spinner: animated working indicator while the agent runs (agent_start →
-- agent_settled), rendered in the PROMPT winbar — always visible at the
-- bottom of the panel, unaffected by chat scrolling.
-- ---------------------------------------------------------------------------

local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

function M.start_spinner()
  if M._spinner_timer then return end
  local messages = M._cfg.working_messages
  local message = messages[math.random(#messages)]
  local frame = 1
  M._spinner_timer = vim.uv.new_timer()
  M._spinner_timer:start(
    0,
    90,
    vim.schedule_wrap(function()
      if M.input_win and vim.api.nvim_win_is_valid(M.input_win) then
        vim.wo[M.input_win].winbar = (" %s %s… "):format(SPINNER_FRAMES[frame], message)
        frame = (frame % #SPINNER_FRAMES) + 1
      end
    end)
  )
end

function M.stop_spinner()
  if M._spinner_timer then
    M._spinner_timer:stop()
    M._spinner_timer:close()
    M._spinner_timer = nil
  end
  if M.input_win and vim.api.nvim_win_is_valid(M.input_win) then vim.wo[M.input_win].winbar = input_title() end
end

--- Reflect host state in the chat winbar (model · thinking · streaming · tokens).
---@param state PiHostState
function M.update_winbar(state)
  M._last_state = state
  if M.chat_win and vim.api.nvim_win_is_valid(M.chat_win) then vim.wo[M.chat_win].winbar = chat_title() end
end

--- Move the editor↔panel divider by delta columns (positive = wider panel).
--- Splits are real siblings: the editor gives/takes the same columns.
---@param delta integer
function M.resize(delta)
  if not M.is_open() then return end
  local cur = vim.api.nvim_win_get_width(M.chat_win)
  local new = math.max(24, math.min(54, cur + delta))
  if new == cur then return end
  M._width_override = new
  vim.api.nvim_win_set_width(M.chat_win, new)
  vim.api.nvim_win_set_width(M.input_win, new)
end

--- Move the chat↔prompt divider by delta lines. The prompt box can GROW from
--- its configured height but never shrink below it (the starting point).
---@param delta integer
function M.resize_height(delta)
  if not M.is_open() then return end
  local cur = input_height()
  local max_h = math.max(M._cfg.input_height, vim.o.lines - 10)
  local new = math.max(M._cfg.input_height, math.min(max_h, cur + delta))
  if new == cur then return end
  M._input_height_override = new
  vim.api.nvim_win_set_height(M.input_win, new)
end

--- Scroll the chat panel without focusing it (bound to <C-d>/<C-u> in prompt).
---@param direction integer 1 = down half page, -1 = up half page
function M.scroll_chat(direction)
  if not (M.chat_win and vim.api.nvim_win_is_valid(M.chat_win)) then return end
  local keys = direction > 0 and "\x04" or "\x15" -- <C-d> / <C-u>
  vim.api.nvim_win_call(M.chat_win, function() vim.cmd("normal! " .. keys) end)
end

return M
