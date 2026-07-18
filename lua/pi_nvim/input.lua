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
  ---@type { on_close: fun(), scroll: fun(direction:integer) }|nil
  _deps = nil,
}

---@param cfg PiNvimConfig
---@param send_fn fun(text:string)
---@param deps { on_close: fun(), scroll: fun(direction:integer) }
function M.setup(cfg, send_fn, deps)
  M._cfg = cfg
  M._send = send_fn
  M._deps = deps
end

---@return integer
function M.ensure_buf()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then return M.buf end
  M.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M.buf].buftype = "nofile"
  vim.bo[M.buf].bufhidden = "hide"
  vim.bo[M.buf].swapfile = false

  local send = function() M.send() end
  vim.keymap.set("i", "<CR>", function()
    vim.cmd "stopinsert"
    send()
  end, { buffer = M.buf, desc = "Send message to pi" })
  vim.keymap.set("n", "<CR>", send, { buffer = M.buf, desc = "Send message to pi" })
  vim.keymap.set("n", "<Esc>", function()
    if M._deps then M._deps.on_close() end
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
function M.send()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end
  local text = table.concat(vim.api.nvim_buf_get_lines(M.buf, 0, -1, false), "\n")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return end
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, { "" })
  if M._send then M._send(text) end
end

--- Pre-fill the input (e.g. after capturing a selection).
---@param text string
function M.set_text(text)
  M.ensure_buf()
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
end

return M
