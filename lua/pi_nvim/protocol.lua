--- Wire helpers mirroring host/src/protocol.ts (ADR-002). Keep in sync:
--- bump M.version when the host's PROTOCOL_VERSION changes.
local M = { version = 3 }

--- Encode one command as a single LF-terminated JSONL record.
---@param obj table
---@return string
function M.encode(obj) return vim.json.encode(obj) .. "\n" end

--- Decode one JSONL record. Returns nil + error on malformed input;
--- callers decide how loud to be about it.
---@param line string
---@return table|nil, string|nil
function M.decode(line)
  local ok, result = pcall(vim.json.decode, line)
  if not ok then return nil, tostring(result) end
  if type(result) ~= "table" then return nil, "expected a JSON object" end
  return result, nil
end

return M
