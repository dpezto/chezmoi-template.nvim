-- Path/filetype resolution for chezmoi source files.
-- Pure name resolution (attribute stripping) needs no CLI; deploy-target lookups
-- go through the chezmoi binary and are cached so each file costs one spawn.
local M = {}

function M.has_chezmoi()
  return vim.fn.executable("chezmoi") == 1
end

-- Strip chezmoi source-state attribute prefixes/suffixes from a path, returning
-- the deployed target path (e.g. private_dot_zshrc.tmpl -> .zshrc). Pure string
-- transform: works without the chezmoi binary and on paths outside the source dir.
function M.resolve_path(name)
  local parts = {}
  local is_abs = name:sub(1, 1) == "/"
  for part in name:gmatch("[^/]+") do
    local changed = true
    while changed do
      changed = false
      local new_part = part
        :gsub("^private_", "")
        :gsub("^readonly_", "")
        :gsub("^executable_", "")
        :gsub("^run_once_", "")
        :gsub("^run_onchange_", "")
        :gsub("^run_", "")
        :gsub("^encrypted_", "")
        :gsub("^exact_", "")
        :gsub("^empty_", "")
      if new_part ~= part then
        part = new_part
        changed = true
      end
    end
    part = part:gsub("^dot_", "."):gsub("%.age$", ""):gsub("%.asc$", ""):gsub("%.tmpl$", "")
    table.insert(parts, part)
  end
  local resolved = table.concat(parts, "/")
  if is_abs then
    resolved = "/" .. resolved
  end
  return resolved
end

-- false = resolution failed (distinct from "not resolved yet")
local source_cache = "unset"

function M.source_dir()
  if source_cache ~= "unset" then
    return source_cache or nil
  end
  local dir = require("chezmoi-template").config.source_dir
  if not dir then
    if not M.has_chezmoi() then
      source_cache = false
      return nil
    end
    local ret = vim.system({ "chezmoi", "source-path" }, { text = true }):wait()
    if ret.code ~= 0 then
      source_cache = false
      return nil
    end
    dir = vim.trim(ret.stdout)
  end
  dir = vim.fs.normalize(vim.fn.expand(dir))
  if dir:sub(-1) ~= "/" then
    dir = dir .. "/"
  end
  source_cache = dir
  return dir
end

function M.is_managed(filepath)
  local dir = M.source_dir()
  if not dir then
    return false
  end
  -- fnamemodify(:p) makes a relative buffer name absolute (and expands ~) —
  -- vim.fs.normalize alone leaves a relative path relative, which would fail
  -- this prefix check.
  local normalized = vim.fs.normalize(vim.fn.fnamemodify(filepath, ":p"))
  return normalized:sub(1, #dir) == dir
end

local target_cache = {}

-- Deployed target path for a source file via `chezmoi target-path`.
-- Returns nil for files with no deploy target (.chezmoitemplates/ partials,
-- special files) or when chezmoi is unavailable.
function M.target_path(file)
  local cached = target_cache[file]
  if cached ~= nil then
    return cached or nil
  end
  if not M.has_chezmoi() then
    return nil
  end
  local ret = vim.system({ "chezmoi", "target-path", file }, { text = true }):wait()
  local target = ret.code == 0 and vim.trim(ret.stdout) or false
  target_cache[file] = target
  return target or nil
end

-- Filetype for a target path.
-- 1. Lua vim.filetype.match covers almost everything.
-- 2. Fallback scratch buffer + :doautocmd BufRead for Vimscript ftdetect globs;
--    real lines are loaded so bigfile-style plugins don't see a 1-line huge file.
function M.target_ft(target)
  local ft = vim.filetype.match({ filename = target })
  if ft and ft ~= "" then
    return ft
  end
  local scratch = vim.api.nvim_create_buf(false, true)
  local escaped = vim.fn.fnameescape(target)
  vim.api.nvim_buf_call(scratch, function()
    vim.cmd("silent! file " .. escaped)
    if vim.fn.filereadable(target) == 1 then
      local lines = vim.fn.readfile(target)
      vim.api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
    end
    vim.cmd("silent! doautocmd BufRead " .. escaped)
  end)
  ft = vim.bo[scratch].filetype
  vim.api.nvim_buf_delete(scratch, { force = true })
  if ft ~= "" then
    return ft
  end
end

-- Absolute target paths of all managed files, cached after one
-- `chezmoi managed` call (single spawn; O(1) lookups afterwards).
local managed_cache

function M.managed_set()
  if managed_cache then
    return managed_cache
  end
  managed_cache = {}
  if M.has_chezmoi() then
    local ret = vim.system(
      { "chezmoi", "managed", "--path-style", "absolute", "--include", "files" },
      { text = true }
    ):wait()
    if ret.code == 0 then
      for line in ret.stdout:gmatch("[^\n]+") do
        managed_cache[vim.fs.normalize(line)] = true
      end
    end
  end
  return managed_cache
end

-- Render template text through `chezmoi execute-template` (async).
-- cb receives the vim.system result ({code, stdout, stderr}).
function M.execute_template(text, cb)
  if not M.has_chezmoi() then
    return cb({ code = 1, stdout = "", stderr = "chezmoi executable not found" })
  end
  vim.system({ "chezmoi", "execute-template" }, { stdin = text, text = true, timeout = 10000 }, cb)
end

-- Template data (`chezmoi data`), cached per session.
local data_cache

function M.data()
  if data_cache ~= nil then
    return data_cache or nil
  end
  data_cache = false
  if M.has_chezmoi() then
    local ret = vim.system({ "chezmoi", "data", "--format", "json" }, { text = true }):wait()
    if ret.code == 0 then
      local ok, decoded = pcall(vim.json.decode, ret.stdout)
      if ok and type(decoded) == "table" then
        data_cache = decoded
      end
    end
  end
  return data_cache or nil
end

-- Record the target filetype/language on the buffer for the inject-chezmoi!
-- directive and the conform formatter to read.
function M.seed(buf, ft)
  if not ft or ft == "" then
    return
  end
  vim.b[buf].chezmoi_target_ft = ft
  if ft ~= "gotmpl" then
    local lang = vim.treesitter.language.get_lang(ft) or ft
    if pcall(vim.treesitter.language.add, lang) then
      vim.b[buf].chezmoi_target_lang = lang
    end
  end
end

return M
