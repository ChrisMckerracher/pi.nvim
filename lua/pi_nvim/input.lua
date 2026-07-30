--- Input box: the prompt float at the bottom of the panel — the ONLY
--- focusable surface. <CR> sends (insert and normal mode), <C-j> inserts a
--- newline (native), <Esc> closes the panel, <C-d>/<C-u> scroll the chat.
local M = {
  ---@type integer|nil
  buf = nil,
  ---@type PiNvimConfig|nil
  _cfg = nil,
  ---@type fun(text:string)|nil
  _send = nil,
  ---@type { on_escape: fun(), on_close: fun(), scroll: fun(direction:integer) }|nil
  _deps = nil,
}

---@param cfg PiNvimConfig
---@param send_fn fun(text:string)
---@param deps { on_escape: fun(), on_close: fun(), scroll: fun(direction:integer) }
function M.setup(cfg, send_fn, deps)
  M._cfg = cfg
  M._send = send_fn
  M._deps = deps
end

---@return integer
function M.ensure_buf()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then return M.buf end
  M.buf = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, M.buf, "pi://prompt")
  vim.bo[M.buf].buftype = "nofile"
  vim.bo[M.buf].bufhidden = "hide"
  vim.bo[M.buf].swapfile = false

  local send = function() M.send() end
  vim.keymap.set("i", "<CR>", send, { buffer = M.buf, desc = "Send message to pi" })
  vim.keymap.set("n", "<CR>", send, { buffer = M.buf, desc = "Send message to pi" })
  -- Unified sidebar contract: Esc returns to the editor (panel stays open),
  -- q closes the panel.
  vim.keymap.set("n", "<Esc>", function()
    if M._deps and M._deps.on_escape then M._deps.on_escape() end
  end, { buffer = M.buf, desc = "Back to editor" })
  vim.keymap.set("n", "q", function()
    if M._deps and M._deps.on_close then M._deps.on_close() end
  end, { buffer = M.buf, desc = "Close pi panel" })
  for _, mode in ipairs { "i", "n" } do
    vim.keymap.set(mode, "<C-d>", function()
      if M._deps then M._deps.scroll(1) end
    end, { buffer = M.buf, desc = "Scroll pi chat down" })
    vim.keymap.set(mode, "<C-u>", function()
      if M._deps then M._deps.scroll(-1) end
    end, { buffer = M.buf, desc = "Scroll pi chat up" })
  end
  return M.buf
end

--- Read, clear, and dispatch the input text via the registered send function.
--- Read, clear, and dispatch the input text via the registered send function.
--- Sending is not a mode change: the user stays in insert mode, still typing.
function M.send()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end
  local text = table.concat(vim.api.nvim_buf_get_lines(M.buf, 0, -1, false), "\n")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return end
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, { "" })
  if M._send then M._send(text) end
  local win = vim.fn.win_findbuf(M.buf)[1]
  if win and vim.api.nvim_get_current_win() == win then vim.cmd "startinsert" end
end

--- Pre-fill the input (e.g. after capturing a selection).
---@param text string
function M.set_text(text)
  M.ensure_buf()
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
end

--- Omni-completion for @file mentions (invoked with <C-x><C-o> after `@`).
--- Only engages when the token under the cursor starts with `@`.
---@param findstart integer 1 = locate start, 0 = return matches
---@param base string
---@return integer|string[]
function M.omnifunc(findstart, base)
  if findstart == 1 then
    local line = vim.api.nvim_get_current_line()
    local start = vim.fn.col "." - 1
    while start > 0 and line:sub(start, start):match "[%w%._%~%-%/]" do
      start = start - 1
    end
    -- 1-based index of '@' equals the 0-based completion start column.
    if line:sub(start, start) == "@" then return start end
    return -3 -- no completion, stay silent
  end
  local items = {}
  for _, file in ipairs(vim.fn.getcompletion(base .. "*", "file")) do
    items[#items + 1] = { word = file, abbr = file, menu = "@file" }
  end
  return items
end

return M
