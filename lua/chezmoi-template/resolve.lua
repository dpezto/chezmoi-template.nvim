-- Path/filetype resolution for chezmoi source files.
-- Pure name resolution (attribute stripping) needs no CLI; deploy-target lookups
-- go through the chezmoi binary and are cached so each file costs one spawn.
local M = {}

function M.has_chezmoi()
  return vim.fn.executable("chezmoi") == 1
end

-- The one place chezmoi is spawned (feature modules must not call vim.system
-- for chezmoi directly). opts goes to vim.system verbatim — pass {} for raw
-- bytes (encryption round-trips), { text = true } for text output. Async when
-- cb is given; sync callers chain :wait().
function M.chezmoi(args, opts, cb)
  local cmd = { "chezmoi" }
  vim.list_extend(cmd, args)
  return vim.system(cmd, opts, cb)
end

-- Strip chezmoi source-state attribute prefixes/suffixes from a path, returning
-- the deployed target path (e.g. private_dot_zshrc.tmpl -> .zshrc). Pure string
-- transform: works without the chezmoi binary and on paths outside the source dir.
function M.resolve_path(name)
  -- normalize converts `\` to `/` on Windows. The path root must survive as a
  -- prefix, not be attribute-stripped as a path component: a drive letter
  -- ("C:/"), a UNC share ("//server/share"), or the POSIX root ("/"). The
  -- drive/UNC matches can't hit a normal Unix path (those begin with "/"), so
  -- this needs no has("win32") gate and stays exercised on the Linux/macOS CI.
  name = vim.fs.normalize(name)
  -- The prefix must end in "/" so `prefix .. concat(parts, "/")` keeps the
  -- separator (gmatch drops the leading slash of the remainder). "C:/" and "/"
  -- already do; the UNC root is captured with its trailing slash for the same
  -- reason (a bare "//server/share" with no file under it is not a real source
  -- path — source_dir always has a trailing slash).
  local prefix = name:match("^%a:/") -- C:/…
    or name:match("^//[^/]+/[^/]+/") -- //server/share/ (UNC root)
    or (name:sub(1, 1) == "/" and "/") -- POSIX root
    or ""
  local parts = {}
  for part in name:sub(#prefix + 1):gmatch("[^/]+") do
    -- literal_ ends attribute parsing: strip it and take the rest verbatim
    -- (chezmoi does NOT interpret dot_/.tmpl/etc. after it — literal_dot_x -> dot_x).
    local literal = false
    local changed = true
    while changed do
      changed = false
      if part:match("^literal_") then
        part = part:sub(#"literal_" + 1)
        literal = true
        break
      end
      -- scripts: run_[once_|onchange_][before_|after_]name. before_/after_ are
      -- attributes only in this position — a regular file named before_x.txt
      -- keeps its name.
      local script = part:match("^run_once_(.+)") or part:match("^run_onchange_(.+)") or part:match("^run_(.+)")
      if script then
        part = script:gsub("^before_", ""):gsub("^after_", "")
        changed = true
      end
      local new_part = part
        :gsub("^private_", "")
        :gsub("^readonly_", "")
        :gsub("^executable_", "")
        :gsub("^create_", "")
        :gsub("^modify_", "")
        :gsub("^remove_", "")
        :gsub("^symlink_", "")
        :gsub("^encrypted_", "")
        :gsub("^exact_", "")
        :gsub("^external_", "")
        :gsub("^empty_", "")
      if new_part ~= part then
        part = new_part
        changed = true
      end
    end
    if not literal then
      part = part:gsub("^dot_", ".")
      -- a .literal suffix stops suffix parsing: foo.tmpl.literal -> foo.tmpl
      local lit = part:gsub("%.literal$", "")
      if lit ~= part then
        part = lit
      else
        part = part:gsub("%.age$", ""):gsub("%.asc$", ""):gsub("%.tmpl$", "")
      end
    end
    table.insert(parts, part)
  end
  return prefix .. table.concat(parts, "/")
end

-- false = resolution failed (distinct from "not resolved yet")
---@type string|false
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
    local ret = M.chezmoi({ "source-path" }, { text = true }):wait()
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
  local ret = M.chezmoi({ "target-path", file }, { text = true }):wait()
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

-- One `chezmoi managed` spawn -> set of normalized paths, or nil on failure
-- (missing binary, old chezmoi without the path style, no config).
local function managed_listing(style)
  if not M.has_chezmoi() then
    return nil
  end
  local ret = M.chezmoi({ "managed", "--path-style", style, "--include", "files" }, { text = true }):wait()
  if ret.code ~= 0 then
    return nil
  end
  local set = {}
  for line in ret.stdout:gmatch("[^\n]+") do
    set[vim.fs.normalize(line)] = true
  end
  return set
end

-- Absolute target paths of all managed files (single spawn; O(1) lookups).
local managed_cache

function M.managed_set()
  if not managed_cache then
    managed_cache = managed_listing("absolute") or {}
  end
  return managed_cache
end

-- Absolute *source* paths of all managed files. Lets BufReadPre skip a doomed
-- per-file `target-path` spawn for source files with no deploy target
-- (partials, scripts). Returns nil when the listing is unavailable so callers
-- fall back to target_path.
---@type table|false|nil
local source_set_cache

function M.source_set()
  if source_set_cache == nil then
    source_set_cache = managed_listing("source-absolute") or false
  end
  return source_set_cache or nil
end

-- Ordered array of normalized paths for a managed listing style, or nil.
local function managed_array(style)
  if not M.has_chezmoi() then
    return nil
  end
  local ret = M.chezmoi({ "managed", "--path-style", style, "--include", "files" }, { text = true }):wait()
  if ret.code ~= 0 then
    return nil
  end
  local arr = {}
  for line in ret.stdout:gmatch("[^\n]+") do
    arr[#arr + 1] = vim.fs.normalize(line)
  end
  return arr
end

-- Public: all managed files as { source = <abs>, target = <abs> } pairs.
-- `managed` sorts the two path-styles by different keys, so they can't be
-- zipped by index; instead resolve every target's source in one
-- `source-path <t1> <t2> …` spawn, which emits sources in argument order.
-- Uncached (rare call).
function M.list()
  local targets = managed_array("absolute")
  if not targets or #targets == 0 then
    return {}
  end
  -- ponytail: all targets in one argv; fine for normal repos, could hit ARG_MAX
  -- with thousands of long paths — batch if that ever bites.
  local cmd = { "source-path" }
  vim.list_extend(cmd, targets)
  local ret = M.chezmoi(cmd, { text = true }):wait()
  if ret.code ~= 0 then
    return {}
  end
  local sources = {}
  for line in ret.stdout:gmatch("[^\n]+") do
    sources[#sources + 1] = vim.fs.normalize(line)
  end
  local out = {}
  for i, target in ipairs(targets) do
    out[i] = { source = sources[i], target = target }
  end
  return out
end

-- Source path for a deploy target via `chezmoi source-path`, or nil.
function M.source_path(target)
  if not M.has_chezmoi() then
    return nil
  end
  local ret = M.chezmoi({ "source-path", target }, { text = true }):wait()
  if ret.code ~= 0 then
    return nil
  end
  -- normalize to forward slashes, consistent with every other path this module returns
  return vim.fs.normalize(vim.trim(ret.stdout))
end

-- Hard ceiling on a single render — a template stuck on an unauthenticated
-- secret-manager call must not hang the editor's callbacks forever.
-- (config.preview.slow_ms handles merely-slow renders well before this.)
local RENDER_TIMEOUT_MS = 10000

-- Render template text through `chezmoi execute-template` (async).
-- cb receives the vim.system result ({code, stdout, stderr}).
function M.execute_template(text, cb)
  if not M.has_chezmoi() then
    return cb({ code = 1, stdout = "", stderr = "chezmoi executable not found" })
  end
  M.chezmoi({ "execute-template" }, { stdin = text, text = true, timeout = RENDER_TIMEOUT_MS }, cb)
end

-- Template data (`chezmoi data`), cached per session.
local data_cache

function M.data()
  if data_cache ~= nil then
    return data_cache or nil
  end
  data_cache = false
  if M.has_chezmoi() then
    local ret = M.chezmoi({ "data", "--format", "json" }, { text = true }):wait()
    if ret.code == 0 then
      local ok, decoded = pcall(vim.json.decode, ret.stdout)
      if ok and type(decoded) == "table" then
        data_cache = decoded
      end
    end
  end
  return data_cache or nil
end

-- Drop caches that go stale when chezmoi state changes outside Neovim
-- (`chezmoi add`/`forget` in a shell, data edits). Positive target-path
-- mappings survive — they don't change for existing files; negative ones are
-- dropped so newly-added files resolve. Wired to FocusGained in setup().
function M.invalidate()
  managed_cache = nil
  source_set_cache = nil
  data_cache = nil
  for file, target in pairs(target_cache) do
    if target == false then
      target_cache[file] = nil
    end
  end
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
