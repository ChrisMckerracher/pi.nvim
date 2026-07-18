--- :checkhealth pi_nvim
local M = {}

---@return string|nil
local function node_version()
  if vim.fn.executable "node" == 0 then return nil end
  local out = vim.fn.system { "node", "--version" }
  if vim.v.shell_error ~= 0 then return nil end
  return (out:gsub("%s+", ""))
end

---@return string|nil
local function sdk_version(host_dir)
  local pkg = host_dir .. "/node_modules/@earendil-works/pi-coding-agent/package.json"
  if vim.fn.filereadable(pkg) == 0 then return nil end
  local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(pkg), "\n"))
  if not ok or type(decoded) ~= "table" then return nil end
  return decoded.version
end

function M.check()
  local health = vim.health
  health.start "pi_nvim"

  local node = node_version()
  if not node then
    health.error("node not found or not executable", { "Install Node.js >= 22.19" })
  else
    local major, minor = node:match "^v(%d+)%.(%d+)"
    if tonumber(major) > 22 or (tonumber(major) == 22 and tonumber(minor) >= 19) then
      health.ok("node " .. node)
    else
      health.error("node " .. node .. " is too old", { "pi requires Node.js >= 22.19" })
    end
  end

  local ok, pi_nvim = pcall(require, "pi_nvim")
  if not ok then
    health.error("pi_nvim module not loaded: " .. tostring(pi_nvim))
    return
  end
  local cfg = pi_nvim.get_config()
  if not cfg then
    health.warn "setup() has not run yet"
    return
  end

  local host_path = cfg.host_cmd[2]
  if host_path and vim.fn.filereadable(host_path) == 1 then
    health.ok("host built: " .. host_path)
  else
    health.error("host not built: " .. tostring(host_path), { "Run `make build` in the pi.nvim repo" })
  end

  local host_dir = vim.fn.fnamemodify(host_path, ":h:h")
  local version = sdk_version(host_dir)
  if version then
    health.ok("pi SDK " .. version)
  else
    health.warn("pi SDK not found under host/node_modules", { "Run `make install` in the pi.nvim repo" })
  end

  local host = pi_nvim.get_host()
  if host and host.job then
    local model = host.state.model
    health.ok(
      ("host running (pid job %d) — model %s, thinking %s"):format(
        host.job,
        model and (model.provider .. "/" .. model.id) or "?",
        tostring(host.state.thinkingLevel)
      )
    )
  else
    health.info "host not running (spawns on first sidebar open)"
  end
end

return M
