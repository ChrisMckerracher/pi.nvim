--- Sidebar layout: chat window above, input window below, docked right.
--- Owns window geometry and winbars; buffer content belongs to chat/input.
local chat = require "pi_nvim.chat"
local input = require "pi_nvim.input"

local M = {
  ---@type integer|nil
  chat_win = nil,
  ---@type integer|nil
  input_win = nil,
  ---@type PiNvimConfig|nil
  _cfg = nil,
}

---@param cfg PiNvimConfig
function M.setup(cfg) M._cfg = cfg end

---@return boolean
function M.is_open()
  return (M.chat_win ~= nil and vim.api.nvim_win_is_valid(M.chat_win))
    or (M.input_win ~= nil and vim.api.nvim_win_is_valid(M.input_win))
end

---@param win integer
---@param text string
local function set_winbar(win, text)
  if vim.api.nvim_win_is_valid(win) then vim.wo[win].winbar = text end
end

--- Shared window dressing for both sidebar windows.
---@param win integer
local function dress_window(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].winfixwidth = true
end

--- Open the sidebar (no-op if already open; focuses the input window).
function M.open()
  if M.is_open() then
    M.focus_input()
    return
  end
  local cfg = M._cfg
  local chat_buf = chat.ensure_buf()
  local input_buf = input.ensure_buf()

  vim.cmd "botright vsplit"
  M.chat_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(M.chat_win, cfg.width)
  vim.api.nvim_win_set_buf(M.chat_win, chat_buf)
  dress_window(M.chat_win)
  vim.wo[M.chat_win].winfixheight = false

  vim.cmd "belowright split"
  M.input_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(M.input_win, cfg.input_height)
  vim.api.nvim_win_set_buf(M.input_win, input_buf)
  dress_window(M.input_win)
  vim.wo[M.input_win].winfixheight = true

  set_winbar(M.input_win, " message pi — <CR> send · <C-j> newline ")
  M.update_winbar { model = nil, thinkingLevel = "?", isStreaming = false }
  vim.cmd "startinsert"
end

--- Close both windows; buffers persist for the next open.
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

--- Reflect host state in the chat winbar.
---@param state PiHostState
function M.update_winbar(state)
  if not M.chat_win or not vim.api.nvim_win_is_valid(M.chat_win) then return end
  local model = state.model and state.model.id or "no-model"
  local streaming = state.isStreaming and " · …" or ""
  set_winbar(M.chat_win, (" pi · %s · %s%s "):format(model, tostring(state.thinkingLevel), streaming))
end

return M
