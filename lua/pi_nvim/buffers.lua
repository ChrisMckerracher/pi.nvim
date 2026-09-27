--- In-memory editing boundary for unnamed code buffers (ADR-006).
local M = {}
local exposed = {}

---@param buf integer
---@return boolean
function M.is_unnamed(buf)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.api.nvim_buf_is_loaded(buf)
    and vim.bo[buf].buftype == ""
    and vim.api.nvim_buf_get_name(buf) == ""
end

--- Identify and expose a buffer to the agent without assigning a filename.
---@param buf integer
---@return string
function M.describe(buf)
  exposed[buf] = true
  return ("[unnamed buffer %d, changedtick %d; use editor_buffer, not filesystem tools]"):format(
    buf,
    vim.api.nvim_buf_get_changedtick(buf)
  )
end

---@param buf integer
---@return table
local function snapshot(buf)
  return {
    bufferId = buf,
    changedtick = vim.api.nvim_buf_get_changedtick(buf),
    filetype = vim.bo[buf].filetype,
    text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"),
  }
end

--- Validate an agent request and read or edit an exposed unnamed buffer.
--- Throws on invalid/stale requests; caller must send the error to the host.
---@param request table
---@return string JSON snapshot after the operation
function M.request(request)
  local buf = request.bufferId
  assert(type(buf) == "number" and buf > 0 and buf % 1 == 0, "invalid buffer id")
  assert(exposed[buf] and M.is_unnamed(buf), "buffer is no longer an exposed unnamed code buffer")
  local seconds, micros = vim.uv.gettimeofday()
  local now = seconds * 1000 + micros / 1000
  assert(type(request.expiresAt) == "number" and now < request.expiresAt, "buffer request expired")
  assert(request.action == "read" or request.action == "edit", "invalid buffer action")
  local current = snapshot(buf)
  if request.action == "read" then return vim.json.encode(current) end

  assert(vim.bo[buf].modifiable and not vim.bo[buf].readonly, "buffer is not writable")
  assert(request.changedtick == current.changedtick, "buffer changed; read it again before editing")
  local old, new = request.oldText, request.newText
  assert(type(old) == "string" and type(new) == "string", "edit requires oldText and newText strings")
  local first, last
  if old == "" then
    assert(current.text == "", "empty oldText is only valid for an empty buffer")
    first, last = 1, 0
  else
    first, last = current.text:find(old, 1, true)
    assert(first, "oldText not found in buffer")
    assert(not current.text:find(old, first + 1, true), "oldText is ambiguous; include more surrounding text")
  end
  local updated = current.text:sub(1, first - 1) .. new .. current.text:sub(last + 1)
  if updated ~= current.text then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(updated, "\n", { plain = true }))
  end
  return vim.json.encode(snapshot(buf))
end

return M
