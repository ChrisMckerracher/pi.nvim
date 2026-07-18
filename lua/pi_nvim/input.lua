--- Input box: the prompt buffer at the bottom of the sidebar.
--- <CR> sends (insert and normal mode), <C-j> inserts a newline (native).
local M = {
  ---@type integer|nil
  buf = nil,
  ---@type PiNvimConfig|nil
  _cfg = nil,
  ---@type fun(text:string)|nil
  _send = nil,
}

---@param cfg PiNvimConfig
---@param send_fn fun(text:string)
function M.setup(cfg, send_fn)
  M._cfg = cfg
  M._send = send_fn
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
