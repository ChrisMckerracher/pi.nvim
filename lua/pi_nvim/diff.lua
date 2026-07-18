--- Diff review (ADR-004): collect per-edit unified patches streamed in
--- tool_execution_end events, list changed files per agent run, show a
--- native diff of before/after, and reject by reverse-applying the patch.
--- No git plugin; `git apply` works outside repositories.
local M = {
  ---@type table<string, { patches: string[] }>
  changes = {},
  ---@type PiNvimConfig|nil
  _cfg = nil,
  ---@type integer|nil scratch buffer holding the "before" content
  _before_buf = nil,
}

---@param cfg PiNvimConfig
function M.setup(cfg) M._cfg = cfg end

--- New agent run → fresh change set.
function M.reset() M.changes = {} end

--- Record a patch from a tool_execution_end event, when present.
---@param evt table
function M.on_tool_end(evt)
  if evt.type ~= "tool_execution_end" then return end
  local result = evt.result
  if type(result) ~= "table" or type(result.details) ~= "table" then return end
  local patch = result.details.patch
  if type(patch) ~= "string" or patch == "" then return end
  local path = "unknown"
  if type(evt.args) == "table" and type(evt.args.path) == "string" then path = evt.args.path end
  M.changes[path] = M.changes[path] or { patches = {} }
  table.insert(M.changes[path].patches, patch)
end

---@return boolean
function M.has_changes() return next(M.changes) ~= nil end

--- Patches chained: each assumes the previous was applied, so undoing means
--- reverse-applying in reverse arrival order.
---@param path string
---@return string
local function combined_reverse_patch(path)
  local entry = M.changes[path]
  local reversed = {}
  for i = #entry.patches, 1, -1 do
    local patch = entry.patches[i]
    if patch:sub(-1) ~= "\n" then patch = patch .. "\n" end
    reversed[#reversed + 1] = patch
  end
  return table.concat(reversed, "")
end

--- Rewrite absolute ---/+++ header paths as a/-prefixed relative ones, so a
--- reverse-apply inside a temp mirror can never touch the real file (only
--- used for display reconstruction; reject() uses the raw patch).
---@param patch string
---@return string
local function relativize_patch_paths(patch)
  patch = patch:gsub("^(%-%-%-%s+)/", "%1a/")
  patch = patch:gsub("\n(%-%-%-%s+)/", "\n%1a/")
  patch = patch:gsub("^(%+%+%+%s+)/", "%1b/")
  patch = patch:gsub("\n(%+%+%+%s+)/", "\n%1b/")
  return patch
end

--- Detect the -p level git apply needs, from the patch --- header.
--- pi's generateUnifiedPatch (jsdiff createTwoFilesPatch, FILE_HEADERS_ONLY)
--- emits `--- <path>` / `+++ <path>` with NO a/ b/ prefix, path exactly as
--- the agent passed it (relative or absolute). Verified against pi 0.80.10
--- source (core/tools/edit-diff.js).
---@param patch string
---@return string plevel, boolean unsafe
function M._patch_mode(patch)
  local header = patch:match "^%-%-%-%s+(%S+)"
  if header and header:sub(1, 2) == "a/" then return "-p1", false end
  if header and header:sub(1, 1) == "/" then return "-p0", true end
  return "-p0", false
end

--- The file path from the patch's first --- header.
---@param patch string
---@return string|nil
local function header_path(patch) return patch:match "^%-%-%-%s+(%S+)" end

--- Run `git apply` with the patch on stdin; cb(ok, stderr).
---@param args string[]
---@param cwd string
---@param patch string
---@param cb fun(ok:boolean, err:string)
local function git_apply(args, cwd, patch, cb)
  vim.system(vim.list_extend({ "git", "apply" }, args), { cwd = cwd, stdin = patch, text = true }, function(out)
    vim.schedule(function() cb(out.code == 0, out.stderr or "") end)
  end)
end

--- Reconstruct the pre-edit content by reverse-applying patches to a mirror
--- of the current file inside a temp dir. The mirror path derives from the
--- patch HEADER path (not the cwd-relative path) so relative and absolute
--- patches both land exactly. cb(before_lines|nil, err).
---@param path string
---@param cb fun(lines:string[]|nil, err:string|nil)
function M._reconstruct(path, cb)
  local patch = combined_reverse_patch(path)
  local hpath = header_path(patch) or path
  local is_abs = hpath:sub(1, 1) == "/"
  local mirror_rel = is_abs and hpath:sub(2) or hpath
  local tmpdir = vim.fn.tempname()
  local mirror = tmpdir .. "/" .. mirror_rel
  vim.fn.mkdir(vim.fn.fnamemodify(mirror, ":h"), "p")

  local ok_read, current = pcall(vim.fn.readfile, path)
  if not ok_read then
    cb(nil, "cannot read " .. path)
    return
  end
  vim.fn.writefile(current, mirror)

  local apply_patch, args
  if is_abs then
    apply_patch = relativize_patch_paths(patch)
    args = { "-R", "-p1" }
  else
    apply_patch = patch
    args = { "-R", "-p0" }
  end
  git_apply(args, tmpdir, apply_patch, function(ok, err)
    if not ok then
      cb(nil, "reverse-apply failed (file may have changed after the edit): " .. err:sub(1, 200))
      return
    end
    local ok_lines, lines = pcall(vim.fn.readfile, mirror)
    pcall(vim.fn.delete, tmpdir, "rf")
    if not ok_lines then
      cb(nil, "cannot read reconstructed file")
      return
    end
    cb(lines)
  end)
end

--- Changed-files picker → native diff view.
function M.review()
  if not M.has_changes() then
    vim.notify("pi: no agent changes recorded this run", vim.log.levels.INFO)
    return
  end
  local paths = vim.tbl_keys(M.changes)
  table.sort(paths)
  vim.ui.select(paths, { prompt = "Review pi change" }, function(choice)
    if choice then M.show(choice) end
  end)
end

--- Show native diff: reconstructed "before" (left) vs current file (right).
---@param path string
function M.show(path)
  M._reconstruct(path, function(before_lines, err)
    if not before_lines then
      vim.notify("pi: " .. (err or "reconstruction failed"), vim.log.levels.WARN)
      return
    end
    local before_buf = vim.api.nvim_create_buf(false, true)
    M._before_buf = before_buf
    vim.api.nvim_buf_set_lines(before_buf, 0, -1, false, before_lines)
    vim.bo[before_buf].buftype = "nofile"
    vim.bo[before_buf].bufhidden = "wipe"
    vim.bo[before_buf].modifiable = false
    local ft = vim.filetype.match { filename = path }
    if ft then vim.bo[before_buf].filetype = ft end

    -- Left: before scratch. Right: the real file. Both in diff mode.
    vim.cmd "topleft vertical new"
    local before_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(before_win, before_buf)
    vim.cmd("vertical diffsplit " .. vim.fn.fnameescape(path))
    local file_win = vim.api.nvim_get_current_win()
    vim.cmd "diffthis"
    vim.api.nvim_set_current_win(before_win)
    vim.cmd "diffthis"

    vim.keymap.set("n", "q", function()
      pcall(vim.api.nvim_win_close, file_win, true)
      pcall(vim.api.nvim_win_close, before_win, true)
    end, { buffer = before_buf, desc = "Close pi diff review" })
  end)
end

--- Reject a file's changes: reverse-apply the agent's patches to the real
--- file. Falls back to an explicit, opt-in `git checkout` for tracked files.
---@param path string
function M.reject(path)
  if not M.changes[path] then
    vim.notify("pi: no recorded changes for " .. path, vim.log.levels.WARN)
    return
  end
  vim.ui.select({ "Reject changes", "Cancel" }, { prompt = "Reject pi's changes to " .. path .. "?" }, function(choice)
    if choice ~= "Reject changes" then return end
    local patch = combined_reverse_patch(path)
    local plevel, unsafe = M._patch_mode(patch)
    local args = { "-R", plevel }
    if unsafe then args[#args + 1] = "--unsafe-paths" end
    git_apply(args, vim.uv.cwd() or ".", patch, function(ok, err)
      if ok then
        M.changes[path] = nil
        vim.notify("pi: reverted " .. path, vim.log.levels.INFO)
        vim.cmd "checktime"
        return
      end
      vim.notify(
        ("pi: reverse patch failed for %s (file drifted?). Reject manually.\n%s"):format(path, err:sub(1, 200)),
        vim.log.levels.ERROR
      )
    end)
  end)
end

return M
