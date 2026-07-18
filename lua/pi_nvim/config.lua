--- pi_nvim configuration: defaults + boundary validation (lua.md rule 5).
---@class PiNvimConfig
---@field width number Panel width: fraction of columns (0 < width < 1) or absolute columns
---@field input_height integer Input window height in lines
---@field host_cmd string[] Command used to spawn the pi.nvim host
---@field auto_scroll boolean Keep the chat pinned to the bottom while streaming
---@field render_thinking boolean Show thinking blocks in the chat buffer
---@field tool_result_lines integer Max lines shown per tool result
---@field max_context_file_lines integer Line cap for @file mention expansion
---@field editor_context boolean Attach compact editor state to every prompt
---@field keymaps boolean Register the default <leader>a… keymaps
---@field working_messages string[] Spinner verbs shown while the agent runs
local M = {}

--- Absolute path of the repo root, derived from this file's location.
---@return string
local function repo_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":h:h:h")
end

---@return PiNvimConfig
function M.defaults()
  return {
    width = 0.32, -- fraction of columns, clamped [24, 54] (small screen ↔ 1440p)
    input_height = 6,
    host_cmd = { "node", repo_root() .. "/host/dist/main.js" },
    auto_scroll = true,
    render_thinking = false, -- thinking collapses to a dim summary line; true streams raw
    tool_result_lines = 12,
    max_context_file_lines = 200,
    editor_context = true,
    keymaps = true,
    working_messages = {
      "Loading",
      "Thinking",
      "Pondering",
      "Cooking",
      "Crunching",
      "Brewing",
      "Cogitating",
      "Tinkering",
      "Ruminating",
      "Forging",
    },
  }
end

--- Merge user options over defaults and validate at the boundary.
---@param opts table|nil
---@return PiNvimConfig
function M.merge(opts)
  local cfg = vim.tbl_deep_extend("force", M.defaults(), opts or {})
  M.validate(cfg)
  return cfg
end

---@param cfg PiNvimConfig
function M.validate(cfg)
  local function expect(name, value, kind)
    if type(value) ~= kind then
      error(("pi_nvim config: %s must be a %s (got %s)"):format(name, kind, type(value)), 3)
    end
  end
  expect("width", cfg.width, "number")
  if cfg.width <= 0 then error("pi_nvim config: width must be positive", 3) end
  expect("input_height", cfg.input_height, "number")
  expect("host_cmd", cfg.host_cmd, "table")
  expect("host_cmd[1]", cfg.host_cmd[1], "string")
  expect("auto_scroll", cfg.auto_scroll, "boolean")
  expect("render_thinking", cfg.render_thinking, "boolean")
  expect("tool_result_lines", cfg.tool_result_lines, "number")
  expect("max_context_file_lines", cfg.max_context_file_lines, "number")
  expect("editor_context", cfg.editor_context, "boolean")
  expect("keymaps", cfg.keymaps, "boolean")
  expect("working_messages", cfg.working_messages, "table")
  if #cfg.working_messages == 0 then error("pi_nvim config: working_messages must not be empty", 3) end
end

--- Resolve the configured width to concrete columns for the current editor.
---@param cfg PiNvimConfig
---@return integer
function M.resolve_width(cfg)
  if cfg.width < 1 then return math.max(24, math.min(54, math.floor(vim.o.columns * cfg.width))) end
  return math.min(math.floor(cfg.width), math.floor(vim.o.columns * 0.5))
end

return M
