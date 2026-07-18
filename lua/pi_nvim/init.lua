--- pi_nvim — public API and wiring.
--- Embeds pi (the coding agent) in Neovim via the pi.nvim host (ADR-001).
local config_mod = require "pi_nvim.config"
local Host = require "pi_nvim.host"
local chat = require "pi_nvim.chat"
local context = require "pi_nvim.context"
local diff = require "pi_nvim.diff"
local input = require "pi_nvim.input"
local sessions = require "pi_nvim.sessions"
local sidebar = require "pi_nvim.sidebar"

local M = {}

---@type PiNvimConfig|nil
M._cfg = nil
---@type PiHost|nil
M._host = nil

---@return PiNvimConfig|nil
function M.get_config() return M._cfg end

---@return PiHost|nil
function M.get_host() return M._host end

--- Ensure the host job is running, then invoke cb.
---@param cb fun()
function M._ensure_host(cb)
  local host = M._host
  if host.job then
    cb()
    return
  end
  host:start(function(ok, err)
    if not ok then
      vim.notify("pi: " .. (err or "host failed to start"), vim.log.levels.ERROR)
      return
    end
    sidebar.update_winbar(host.state)
    cb()
  end)
end

--- Answer the agent-pull editor_context tool (ADR-005). Always responds —
--- a silent answer would hang the tool until timeout.
---@param request_id string
function M._answer_editor_context(request_id)
  local ok, ctx = pcall(context.editor_state_full)
  M._host:notify("editor_context_response", {
    requestId = request_id,
    context = ok and ctx or ("editor context unavailable: " .. tostring(ctx)),
  })
end

--- Send composed text to the agent: prompt when idle, steer while streaming.
---@param text string
function M._send(text)
  M._ensure_host(function()
    local message, attached = context.compose(text, M._cfg)
    local note = attached
        and ("+ " .. attached.kind .. ": " .. attached.path .. (attached.start_line and (" lines " .. attached.start_line .. "-" .. attached.end_line) or ""))
      or nil
    chat.echo_user(text, note)
    sidebar.open()
    local cmd = M._host:is_streaming() and "steer" or "prompt"
    M._host:request(cmd, { message = message }, function(resp)
      if not resp.success then chat.show_error(resp.error or "send failed") end
    end)
    sidebar.update_winbar(M._host.state)
  end)
end

--- Toggle the sidebar (spawns the host on first open).
function M.toggle()
  sidebar.toggle()
  if sidebar.is_open() then M._ensure_host(function() end) end
end

--- <leader>as: capture visual selection → sidebar with input focused.
function M.send_selection()
  context.capture_visual()
  sidebar.open()
  M._ensure_host(function() end)
  sidebar.focus_input()
end

--- <leader>af: capture current file → sidebar with input focused.
function M.send_file()
  context.capture_file()
  sidebar.open()
  M._ensure_host(function() end)
  sidebar.focus_input()
end

--- <leader>ak: Ctrl+K-style inline edit of the visual selection (warm session).
function M.inline_edit()
  context.capture_visual()
  vim.ui.input({ prompt = "Inline edit instruction: " }, function(instruction)
    if not instruction or instruction == "" then
      context.consume()
      return
    end
    M._ensure_host(function()
      local message = context.compose("", M._cfg)
      message = "[inline edit — modify the file directly with your edit tool]\n" .. instruction .. "\n\n" .. message
      chat.echo_user("✂ " .. instruction, "+ selection")
      sidebar.open()
      local cmd = M._host:is_streaming() and "steer" or "prompt"
      M._host:request(cmd, { message = message }, function(resp)
        if not resp.success then chat.show_error(resp.error or "send failed") end
      end)
    end)
  end)
end

--- <leader>ad: review/revert what the agent changed this run.
function M.review_changes() diff.review() end

--- <leader>aD: reject a changed file (reverse patch) after choosing it.
function M.reject_change()
  if not diff.has_changes() then
    vim.notify("pi: no agent changes recorded this run", vim.log.levels.INFO)
    return
  end
  local paths = vim.tbl_keys(diff.changes)
  table.sort(paths)
  vim.ui.select(paths, { prompt = "Reject changes in…" }, function(choice)
    if choice then diff.reject(choice) end
  end)
end

--- <leader>an: start a fresh session.
function M.new_session()
  M._ensure_host(function()
    M._host:request("new_session", {}, function(resp)
      if not resp.success then
        vim.notify("pi: " .. (resp.error or "new_session failed"), vim.log.levels.ERROR)
        return
      end
      M._host.state = resp.data
      chat.note "new session started"
      sidebar.update_winbar(M._host.state)
    end)
  end)
end

--- <leader>ar: resume a past session (shared store — CLI sessions included).
function M.resume_session()
  M._ensure_host(function()
    sessions.pick(M._host, function()
      M._host:request("get_messages", {}, function(resp)
        if resp.success then chat.replay(resp.data) end
        sidebar.update_winbar(M._host.state)
      end)
    end)
  end)
end

--- <leader>at: cycle thinking level.
function M.cycle_thinking()
  M._ensure_host(function()
    M._host:request("cycle_thinking", {}, function(resp)
      if not resp.success then return end
      local level = resp.data and resp.data.level or "?"
      M._host.state.thinkingLevel = level
      sidebar.update_winbar(M._host.state)
      vim.notify("pi thinking: " .. tostring(level), vim.log.levels.INFO)
    end)
  end)
end

--- Abort the in-flight agent run.
function M.abort()
  if M._host and M._host.job then M._host:request("abort", {}) end
end

---@param opts table|nil
function M.setup(opts)
  local cfg = config_mod.merge(opts)
  M._cfg = cfg

  chat.setup(cfg)
  input.setup(cfg, M._send)
  sidebar.setup(cfg)
  diff.setup(cfg)

  local host = Host.new(cfg)
  M._host = host
  host:on_event(function(evt)
    chat.event(evt)
    diff.on_tool_end(evt)
    if evt.type == "editor_context_request" and type(evt.requestId) == "string" then
      M._answer_editor_context(evt.requestId)
    elseif evt.type == "agent_start" then
      diff.reset()
      sidebar.update_winbar(host.state)
    elseif evt.type == "agent_settled" or evt.type == "thinking_level_changed" then
      sidebar.update_winbar(host.state)
    end
  end)

  vim.api.nvim_create_user_command("Pi", function() M.toggle() end, { desc = "Toggle pi sidebar" })
  vim.api.nvim_create_user_command("PiNew", function() M.new_session() end, { desc = "New pi session" })
  vim.api.nvim_create_user_command("PiResume", function() M.resume_session() end, { desc = "Resume pi session" })
  vim.api.nvim_create_user_command("PiReview", function() M.review_changes() end, { desc = "Review pi changes" })
  vim.api.nvim_create_user_command("PiAbort", function() M.abort() end, { desc = "Abort pi agent run" })

  if cfg.keymaps then
    local map = vim.keymap.set
    map("n", "<leader>a", M.toggle, { desc = "Toggle pi sidebar" })
    map("v", "<leader>as", M.send_selection, { desc = "Send selection to pi" })
    map("n", "<leader>af", M.send_file, { desc = "Send current file to pi" })
    map("v", "<leader>ak", M.inline_edit, { desc = "Inline edit with pi" })
    map("n", "<leader>ad", M.review_changes, { desc = "Review pi changes (diff)" })
    map("n", "<leader>aD", M.reject_change, { desc = "Reject pi changes (revert)" })
    map("n", "<leader>an", M.new_session, { desc = "New pi session" })
    map("n", "<leader>ar", M.resume_session, { desc = "Resume pi session" })
    map("n", "<leader>at", M.cycle_thinking, { desc = "Cycle pi thinking level" })
    map("n", "<leader>ax", M.abort, { desc = "Abort pi agent run" })
  end
end

return M
