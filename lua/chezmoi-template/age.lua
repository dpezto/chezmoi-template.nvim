-- Transparent editing of chezmoi-managed *.age files: decrypt on read,
-- re-encrypt on write. Opt-in (config.age.enabled).
--
-- Identity/recipients resolution order:
--   1. config.age.identity / config.age.recipients (string/list or function)
--   2. chezmoi's own encryption config via `chezmoi dump-config`
local M = {}

local resolve = require("chezmoi-template.resolve")

local function cfg()
  return require("chezmoi-template").config.age
end

local dump_cache = "unset"

-- The [age] section of the active chezmoi config (identity, recipient(s), …)
local function chezmoi_age_config()
  if dump_cache == "unset" then
    dump_cache = false
    if resolve.has_chezmoi() then
      local ret = vim.system({ "chezmoi", "dump-config", "--format=json" }, { text = true }):wait()
      if ret.code == 0 then
        local ok, decoded = pcall(vim.json.decode, ret.stdout)
        if ok and type(decoded) == "table" then
          dump_cache = decoded.age or false
        end
      end
    end
  end
  return dump_cache or nil
end

local function resolve_identity()
  local id = cfg().identity
  if type(id) == "function" then
    id = id()
  end
  if id and id ~= "" then
    return vim.fn.expand(id)
  end
  local age = chezmoi_age_config()
  if age then
    if age.identity and age.identity ~= "" then
      return vim.fn.expand(age.identity)
    end
    if type(age.identities) == "table" and age.identities[1] then
      return vim.fn.expand(age.identities[1])
    end
  end
end

local function resolve_recipients()
  local r = cfg().recipients
  if type(r) == "function" then
    r = r()
  end
  if type(r) == "string" then
    r = { r }
  end
  if type(r) == "table" and #r > 0 then
    return r
  end
  local age = chezmoi_age_config()
  if age then
    local out = {}
    if age.recipient and age.recipient ~= "" then
      out[#out + 1] = age.recipient
    end
    for _, v in ipairs(age.recipients or {}) do
      out[#out + 1] = v
    end
    if #out > 0 then
      return out
    end
  end
end

local function read_post(args)
  local identity = resolve_identity()
  if not identity then
    vim.notify("chezmoi-template: no age identity (set config.age.identity)", vim.log.levels.ERROR)
    return
  end
  local ret = vim.system({ cfg().tool, "--decrypt", "-i", identity, args.file }, { text = true }):wait()
  if ret.code ~= 0 then
    vim.notify("chezmoi-template: decryption failed:\n" .. (ret.stderr or ""), vim.log.levels.ERROR)
    return
  end

  local lines = vim.split(ret.stdout, "\n")
  -- stdout ends with \n for text files -> trailing "" from split; drop it and
  -- let 'eol' represent it, matching how nvim reads a normal file.
  if lines[#lines] == "" then
    table.remove(lines)
  else
    vim.bo[args.buf].eol = false
  end
  vim.api.nvim_buf_set_lines(args.buf, 0, -1, false, lines)
  vim.bo[args.buf].binary = false
  vim.bo[args.buf].modified = false

  -- Resolve the deployed filename so the buffer gets its real filetype;
  -- *.tmpl.age additionally routes through gotmpl with the target injected.
  local target = resolve.target_path(args.file)
  if target then
    local ft = vim.filetype.match({ filename = target, buf = args.buf })
    if ft then
      resolve.seed(args.buf, ft)
      vim.bo[args.buf].filetype = args.file:match("%.tmpl") and "gotmpl" or ft
    end
  end
end

local function write_cmd(args)
  local recipients = resolve_recipients()
  if not recipients then
    vim.notify("chezmoi-template: aborting save, no age recipients (set config.age.recipients)", vim.log.levels.ERROR)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  -- POSIX final newline: 'eol' set (default) means the text must end with \n
  if vim.bo[args.buf].eol then
    text = text .. "\n"
  end

  local cmd = { cfg().tool, "--encrypt", "--armor" }
  for _, r in ipairs(recipients) do
    vim.list_extend(cmd, { "-r", r })
  end
  vim.list_extend(cmd, { "-o", args.file })

  local ret = vim.system(cmd, { stdin = text }):wait()
  if ret.code == 0 then
    vim.bo[args.buf].modified = false
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = args.buf, modeline = false })
  else
    vim.notify("chezmoi-template: error saving file:\n" .. (ret.stderr or ""), vim.log.levels.ERROR)
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("chezmoi-template.age", { clear = true })

  vim.api.nvim_create_autocmd("BufReadPre", {
    group = group,
    pattern = "*.age",
    callback = function(ctx)
      -- Excluded paths (e.g. passphrase-encrypted bootstrap keys) and files
      -- outside the source dir open as plain binary.
      for _, pat in ipairs(cfg().exclude) do
        if ctx.file:match(pat) then
          return
        end
      end
      if not resolve.is_managed(ctx.file) then
        return
      end

      vim.bo[ctx.buf].binary = true
      vim.bo[ctx.buf].swapfile = false

      -- Buffer-local: other *.age files won't see these events
      vim.api.nvim_create_autocmd("BufReadPost", {
        group = group,
        buffer = ctx.buf,
        callback = read_post,
      })
      vim.api.nvim_create_autocmd("BufWriteCmd", {
        group = group,
        buffer = ctx.buf,
        callback = write_cmd,
      })
    end,
  })
end

return M
