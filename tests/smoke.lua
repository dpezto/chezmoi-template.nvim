-- Driven by tests/smoke.sh. Asserts the plugin against the scratch chezmoi
-- config (mode=config) and graceful degradation without one (mode=noconfig).
vim.opt.rtp:prepend(vim.fn.getcwd())

local mode = os.getenv("CHEZMOI_SMOKE_MODE")
local src_env = assert(os.getenv("CHEZMOI_SMOKE_SRC"), "CHEZMOI_SMOKE_SRC not set")

require("chezmoi-template").setup({ encryption = { enabled = true } })
local resolve = require("chezmoi-template.resolve")

local function check(name, ok, extra)
  if not ok then
    io.stderr:write(("smoke FAIL %s%s\n"):format(name, extra and (": " .. tostring(extra)) or ""))
    os.exit(1)
  end
  print("smoke ok   " .. name)
end

if mode == "noconfig" then
  -- No chezmoi config: nothing may error; templates still open as gotmpl
  local tmpl = src_env .. "/orphan.tmpl"
  local f = assert(io.open(tmpl, "w"))
  f:write("{{ .foo }}\n")
  f:close()
  local ok, err = pcall(vim.cmd.edit, tmpl)
  check("open unmanaged tmpl", ok, err)
  check("gotmpl filetype", vim.bo.filetype == "gotmpl", vim.bo.filetype)
  check("not managed", resolve.is_managed(tmpl) == false)
  local hok, herr = pcall(vim.cmd, "checkhealth chezmoi-template")
  check("checkhealth runs", hok, herr)
  print("smoke noconfig passed")
  return
end

local src = vim.fs.normalize(src_env) .. "/"
check("source_dir", resolve.source_dir() == src, tostring(resolve.source_dir()))

local zshrc = src .. "dot_zshrc.tmpl"
local target = resolve.target_path(zshrc)
check("target_path", target and target:match("%.zshrc$"), tostring(target))

local sset = resolve.source_set()
check("source_set has zshrc", sset and sset[vim.fs.normalize(zshrc)] ~= nil)

vim.cmd.edit(zshrc)
check("tmpl filetype", vim.bo.filetype == "gotmpl", vim.bo.filetype)
check("target ft seeded", vim.b.chezmoi_target_ft == "zsh", tostring(vim.b.chezmoi_target_ft))

vim.cmd.edit(src .. ".chezmoitemplates/oshelper")
check("partial forced gotmpl", vim.bo.filetype == "gotmpl", vim.bo.filetype)

local done, res
resolve.execute_template("{{ .chezmoi.os }}", function(r)
  res = r
  done = true
end)
vim.wait(5000, function()
  return done
end)
check("execute_template renders", done and res.code == 0 and res.stdout:match("%a"), res and res.stderr)

done = false
resolve.execute_template("{{ if }}", function(r)
  res = r
  done = true
end)
vim.wait(5000, function()
  return done
end)
check("template error surfaces", done and res.code ~= 0)
check("diagnostics parse", type(require("chezmoi-template.diagnostics").parse(res.stderr or "")) == "table")

local enc = src .. "encrypted_dot_token.asc"
if vim.fn.filereadable(enc) == 1 then
  vim.cmd.edit(enc)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  check("gpg decrypt on open", lines[1] == "s3cret", vim.inspect(lines))
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "s3cret2" })
  vim.cmd.write()
  local out = vim.system({ "chezmoi", "decrypt", enc }, { text = true }):wait()
  check("gpg re-encrypt on save", out.code == 0 and vim.trim(out.stdout) == "s3cret2", out.stderr)
end

vim.cmd.edit(zshrc)
vim.cmd("Chezmoi preview")
local rendered
vim.wait(5000, function()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local first = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
    if first:match("^export SMOKE_OS=%a") then
      rendered = first
      return true
    end
  end
  return false
end)
check("preview renders", rendered ~= nil, rendered)

local pbuf, pwin
for _, win in ipairs(vim.api.nvim_list_wins()) do
  local b = vim.api.nvim_win_get_buf(win)
  if vim.api.nvim_buf_get_name(b):match("chezmoi%-preview://") then
    pbuf, pwin = b, win
  end
end
check("preview buffer named after target", pbuf and vim.api.nvim_buf_get_name(pbuf):match("%.zshrc$"))

vim.api.nvim_set_current_win(pwin)
vim.api.nvim_feedkeys("q", "x", false)
check("q closes preview", not vim.api.nvim_buf_is_valid(pbuf))

vim.cmd.edit(src .. ".chezmoiignore")
vim.bo.filetype = "conf" -- simulate a non-template buffer
local wins_before = #vim.api.nvim_list_wins()
local pok, perr = pcall(vim.cmd, "Chezmoi preview")
check("preview refuses non-template", pok and #vim.api.nvim_list_wins() == wins_before, perr)

print("smoke config passed")
