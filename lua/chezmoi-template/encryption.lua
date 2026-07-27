-- Transparent editing of chezmoi-managed encrypted files (*.age, *.asc):
-- decrypt on read, re-encrypt on write. Opt-in (config.encryption.enabled).
-- Delegates to `chezmoi decrypt` / `chezmoi encrypt`, so identities, recipients,
-- and tool choice (age/rage/builtin, even gpg) all come from chezmoi's own
-- encryption config — anyone editing encrypted managed files already has it set.
local M = {}

local resolve = require("chezmoi-template.resolve")

local function cfg()
  return require("chezmoi-template").config.encryption
end

local function decrypt(file)
  -- No text=true: decode raw bytes so line endings (and any binary payload)
  -- round-trip byte-for-byte, symmetric with encrypt() below. text=true would
  -- strip CR from a CRLF config and silently rewrite it to LF on save.
  return resolve.chezmoi({ "decrypt", file }, {}):wait()
end

local function encrypt(text, file)
  local ret = resolve.chezmoi({ "encrypt" }, { stdin = text }):wait()
  if ret.code == 0 then
    local out = io.open(file, "wb")
    if not out then
      return { code = 1, stderr = "cannot open " .. file .. " for writing" }
    end
    -- A failed write (disk full, I/O error) must not report success — the
    -- buffer would be marked unmodified with the file unwritten.
    local wok, werr = out:write(ret.stdout)
    local cok = out:close()
    if not wok or not cok then
      return { code = 1, stderr = "failed writing " .. file .. (werr and ": " .. werr or "") }
    end
  end
  return ret
end

-- A file the transparent layer handles: encryption on, an encrypted suffix,
-- not excluded, inside the source dir. Read per call, not at registration:
-- setup() can run twice (the plugin/ bootstrap with defaults, then a lazy.nvim
-- opts merge), and the second call is usually the one enabling encryption.
-- Excludes (e.g. passphrase-encrypted bootstrap keys) match the normalized
-- (forward-slash) path so patterns are portable — a raw autocmd path is
-- backslashed on Windows and would dodge "/"-style patterns.
local function eligible(file)
  if not cfg().enabled then
    return false
  end
  local nfile = vim.fs.normalize(file)
  if not (nfile:match("%.age$") or nfile:match("%.asc$")) then
    return false
  end
  for _, pat in ipairs(cfg().exclude) do
    if nfile:match(pat) then
      return false
    end
  end
  return resolve.is_managed(file)
end

-- Decrypted text of a managed encrypted file, or nil (encryption off, not an
-- encrypted managed file, excluded, or decryption failed). For read-only
-- consumers like the picker preview; buffers editing the file go through the
-- autocmds below instead.
function M.text(file)
  if not eligible(file) then
    return nil
  end
  local ret = decrypt(file)
  return ret.code == 0 and ret.stdout or nil
end

local function read_post(args)
  local ret = decrypt(args.file)
  if ret.code ~= 0 then
    require("chezmoi-template").notify("decryption failed:\n" .. (ret.stderr or ""), vim.log.levels.ERROR)
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
  local lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  -- POSIX final newline: 'eol' set (default) means the text must end with \n
  if vim.bo[args.buf].eol then
    text = text .. "\n"
  end

  local ret = encrypt(text, args.file)
  if ret.code == 0 then
    vim.bo[args.buf].modified = false
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = args.buf, modeline = false })
  else
    require("chezmoi-template").notify("error saving file:\n" .. (ret.stderr or ""), vim.log.levels.ERROR)
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("chezmoi-template.encryption", { clear = true })

  vim.api.nvim_create_autocmd("BufReadPre", {
    group = group,
    -- .age (age/rage) and .asc (gpg) — chezmoi's encryption suffixes
    pattern = { "*.age", "*.asc" },
    callback = function(ctx)
      -- Disabled, excluded, and unmanaged files open as plain binary
      if not eligible(ctx.file) then
        return
      end
      -- An encrypted file is a managed source file like any other: bring up the
      -- rest of the plugin (commands, apply-on-save, icons) for it too. Safe
      -- here because _activate() no longer touches this module's augroup.
      require("chezmoi-template")._activate()

      -- Never persist decrypted content: no swap, no undo history on disk
      vim.bo[ctx.buf].binary = true
      vim.bo[ctx.buf].swapfile = false
      vim.bo[ctx.buf].undofile = false

      -- Buffer-local: other encrypted files won't see these events
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
