--- pi_nvim — public API and wiring.
--- Embeds pi (the coding agent) in Neovim via the pi.nvim host (ADR-001).
local config_mod = require "pi_nvim.config"
local Host = require "pi_nvim.host"
local chat = require "pi_nvim.chat"
local context = require "pi_nvim.context"
local diff = require "pi_nvim.diff"
local input = require "pi_nvim.input"
local sessions = require "pi_nvim.sessions"
local panel = require "pi_nvim.panel"
local buffers = require "pi_nvim.buffers"

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
    panel.update_winbar(host.state)
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
    panel.open()
    local cmd = M._host:is_streaming() and "steer" or "prompt"
    M._host:request(cmd, { message = message }, function(resp)
      if not resp.success then chat.show_error(resp.error or "send failed") end
    end)
    panel.update_winbar(M._host.state)
  end)
end

--- <leader>a: open when closed, close when visible, regardless of focus.
function M.toggle()
  panel.toggle()
  M._ensure_host(function() end)
end

--- <leader>aq: actually close the panel (Esc in the input also works).
function M.close_panel() panel.close() end

--- <leader>as: capture visual selection → sidebar with input focused.
function M.send_selection()
  context.capture_visual()
  panel.open()
  M._ensure_host(function() end)
  panel.focus_input()
end

--- <leader>af: capture current file → sidebar with input focused.
function M.send_file()
  context.capture_file()
  panel.open()
  M._ensure_host(function() end)
  panel.focus_input()
end

--- <leader>ak: Ctrl+K-style inline edit of the visual selection (warm session).
function M.inline_edit()
  local unnamed = buffers.is_unnamed(vim.api.nvim_get_current_buf())
  context.capture_visual()
  vim.ui.input({ prompt = "Inline edit instruction: " }, function(instruction)
    if not instruction or instruction == "" then
      context.consume()
      return
    end
    M._ensure_host(function()
      local message = context.compose("", M._cfg)
      local directive = unnamed
          and "[inline edit — read the unnamed buffer with editor_buffer, then edit it using its current changedtick; keep it unnamed and unsaved]"
        or "[inline edit — modify the file directly with your edit tool]"
      message = directive .. "\n" .. instruction .. "\n\n" .. message
      chat.echo_user("✂ " .. instruction, "+ selection")
      panel.open()
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
      chat.replay {}
      diff.reset()
      chat.note "new session started"
      panel.update_winbar(M._host.state)
    end)
  end)
end

--- <leader>ar: resume a past session (shared store — CLI sessions included).
function M.resume_session()
  M._ensure_host(function()
    sessions.pick(M._host, function()
      M._host:request("get_messages", {}, function(resp)
        if resp.success then chat.replay(resp.data) end
        panel.update_winbar(M._host.state)
      end)
    end)
  end)
end

--- F2 / :PiSessions: discoverable session actions.
function M.session_menu() sessions.menu { new_session = M.new_session, resume_session = M.resume_session } end

--- <leader>am: pick a model for the current session (session-scoped).
function M.pick_model()
  M._ensure_host(function()
    M._host:request("list_models", {}, function(resp)
      if not resp.success then
        vim.notify("pi: " .. (resp.error or "list_models failed"), vim.log.levels.ERROR)
        return
      end
      vim.ui.select(resp.data, {
        prompt = "Pi model",
        format_item = function(m)
          return (m.isCurrent and "● " or "  ") .. m.provider .. "/" .. m.id .. " — " .. (m.name or "")
        end,
      }, function(choice)
        if not choice then return end
        M._host:request("set_model", { provider = choice.provider, modelId = choice.id }, function(set_resp)
          if not set_resp.success then
            vim.notify("pi: " .. (set_resp.error or "set_model failed"), vim.log.levels.ERROR)
            return
          end
          M._host.state = set_resp.data
          panel.update_winbar(M._host.state)
          chat.note("model → " .. choice.provider .. "/" .. choice.id)
        end)
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
      panel.update_winbar(M._host.state)
      vim.notify("pi thinking: " .. tostring(level), vim.log.levels.INFO)
    end)
  end)
end

--- Abort the in-flight agent run.
function M.abort()
  if not M._host or not M._host.job then
    vim.notify("pi: no active run to stop", vim.log.levels.INFO)
    return
  end
  M._host:request("abort", {}, function(resp)
    if not resp.success then
      chat.show_error(resp.error or "could not stop pi")
      return
    end
    chat.note "stop requested"
  end)
end

---@param opts table|nil
function M.setup(opts)
  local cfg = config_mod.merge(opts)
  M._cfg = cfg

  chat.setup(cfg)
  context.setup()
  input.setup(cfg, M._send, {
    on_close = function() panel.close() end,
    abort = M.abort,
    sessions = M.session_menu,
    scroll = function(direction) panel.scroll_chat(direction) end,
  })
  panel.setup(cfg)
  diff.setup(cfg)

  local host = Host.new(cfg)
  M._host = host
  host:on_event(function(evt)
    chat.event(evt)
    diff.on_tool_end(evt)
    if evt.type == "editor_context_request" and type(evt.requestId) == "string" then
      M._answer_editor_context(evt.requestId)
    elseif evt.type == "editor_buffer_request" and type(evt.requestId) == "string" then
      local ok, result = pcall(buffers.request, evt)
      host:notify("editor_buffer_response", {
        requestId = evt.requestId,
        result = ok and result or ("Error: " .. tostring(result)),
      })
    elseif evt.type == "agent_start" then
      diff.reset()
      panel.start_spinner()
      panel.update_winbar(host.state)
    elseif evt.type == "agent_settled" then
      panel.stop_spinner()
      -- Refresh stats (tokens/cost/context) once per settled run.
      host:request("get_state", {}, function(resp)
        if resp.success then
          host.state = resp.data
          panel.update_winbar(host.state)
        end
      end)
    elseif evt.type == "thinking_level_changed" then
      panel.update_winbar(host.state)
    elseif evt.type == "host_error" then
      panel.stop_spinner()
    end
  end)

  vim.api.nvim_create_user_command("Pi", function() M.toggle() end, { desc = "Toggle pi sidebar" })
  vim.api.nvim_create_user_command("PiSessions", M.session_menu, { desc = "Pi sessions: new or resume" })
  vim.api.nvim_create_user_command("PiNew", function() M.new_session() end, { desc = "New pi session" })
  vim.api.nvim_create_user_command("PiResume", function() M.resume_session() end, { desc = "Resume pi session" })
  vim.api.nvim_create_user_command("PiReview", function() M.review_changes() end, { desc = "Review pi changes" })
  vim.api.nvim_create_user_command("PiAbort", function() M.abort() end, { desc = "Abort pi agent run" })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("PiNvimShutdown", { clear = true }),
    callback = function()
      if M._host then M._host:stop() end
    end,
  })

  if cfg.keymaps then
    local map = vim.keymap.set
    map("n", "<leader>a", M.toggle, { desc = "Toggle pi panel" })
    map("v", "<leader>as", M.send_selection, { desc = "Send selection to pi" })
    map("n", "<leader>af", M.send_file, { desc = "Send current file to pi" })
    map("v", "<leader>ak", M.inline_edit, { desc = "Inline edit with pi" })
    map("n", "<leader>ad", M.review_changes, { desc = "Review pi changes (diff)" })
    map("n", "<leader>aD", M.reject_change, { desc = "Reject pi changes (revert)" })
    map("n", "<leader>aS", M.session_menu, { desc = "Pi sessions: new or resume" })
    map("n", "<leader>an", M.new_session, { desc = "New pi session" })
    map("n", "<leader>ar", M.resume_session, { desc = "Resume pi session" })
    map("n", "<leader>am", M.pick_model, { desc = "Pick pi model" })
    map("n", "<leader>at", M.cycle_thinking, { desc = "Cycle pi thinking level" })
    map("n", "<leader>ax", M.abort, { desc = "Abort pi agent run" })
  end
end

return M
