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
  return vim.system({ "chezmoi", "decrypt", file }, { text = true }):wait()
end

local function encrypt(text, file)
  local ret = vim.system({ "chezmoi", "encrypt" }, { stdin = text }):wait()
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

local function read_post(args)
  local ret = decrypt(args.file)
  if ret.code ~= 0 then
    vim.notify("decryption failed:\n" .. (ret.stderr or ""), vim.log.levels.ERROR, { title = "chezmoi" })
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
    vim.notify("error saving file:\n" .. (ret.stderr or ""), vim.log.levels.ERROR, { title = "chezmoi" })
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("chezmoi-template.encryption", { clear = true })

  vim.api.nvim_create_autocmd("BufReadPre", {
    group = group,
    -- .age (age/rage) and .asc (gpg) — chezmoi's encryption suffixes
    pattern = { "*.age", "*.asc" },
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
