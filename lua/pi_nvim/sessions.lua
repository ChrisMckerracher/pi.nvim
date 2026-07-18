--- Session picker: list project sessions and switch (Phase 4).
--- Sessions live in the shared store — CLI sessions appear here too.
local M = {}

---@param item table SessionListItem from the host
---@return string
local function format_item(item)
  local when = (item.modified or ""):sub(1, 16):gsub("T", " ")
  local title = item.name
  if not title or title == "" then title = (item.firstMessage or ""):gsub("\n", " "):sub(1, 60) end
  local current = item.isCurrent and "●" or " "
  return ("%s %s  (%d)  %s"):format(current, when, item.messageCount or 0, title)
end

--- List sessions for the current project and switch to the chosen one.
---@param host PiHost
---@param on_switched fun() called after a successful switch (chat replay)
function M.pick(host, on_switched)
  host:request("list_sessions", {}, function(resp)
    if not resp.success then
      vim.notify("pi: " .. (resp.error or "list_sessions failed"), vim.log.levels.ERROR)
      return
    end
    local items = resp.data
    if type(items) ~= "table" or #items == 0 then
      vim.notify("pi: no sessions for this project yet", vim.log.levels.INFO)
      return
    end
    vim.ui.select(items, { prompt = "Resume pi session", format_item = format_item }, function(choice)
      if not choice then return end
      host:request("switch_session", { path = choice.path }, function(switch_resp)
        if not switch_resp.success then
          vim.notify("pi: " .. (switch_resp.error or "switch failed"), vim.log.levels.ERROR)
          return
        end
        host.state = switch_resp.data
        on_switched()
      end)
    end)
  end)
end

return M
