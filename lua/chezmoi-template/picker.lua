-- Source-file picker over the chezmoi source directory, backend-agnostic.
-- config.picker picks the backend explicitly; nil auto-detects among loaded
-- pickers (snacks > telescope > fzf-lua > mini.pick) and falls back to
-- vim.ui.select. Auto-detection only sees pickers that are on the runtimepath
-- when invoked — with aggressive lazy-loading, set config.picker explicitly.
local M = {}

local backends = {
  snacks = {
    avail = function()
      return pcall(require, "snacks")
    end,
    open = function(src)
      require("snacks").picker.files({ cwd = src, hidden = true })
    end,
  },
  telescope = {
    avail = function()
      return pcall(require, "telescope.builtin")
    end,
    open = function(src)
      require("telescope.builtin").find_files({ cwd = src, hidden = true })
    end,
  },
  ["fzf-lua"] = {
    avail = function()
      return pcall(require, "fzf-lua")
    end,
    open = function(src)
      require("fzf-lua").files({ cwd = src, hidden = true })
    end,
  },
  mini = {
    avail = function()
      return pcall(require, "mini.pick")
    end,
    open = function(src)
      require("mini.pick").builtin.files(nil, { source = { cwd = src } })
    end,
  },
  select = {
    avail = function()
      return true
    end,
    open = function(src)
      -- Managed source files via chezmoi itself; no external picker needed
      local ret = vim
        .system({ "chezmoi", "managed", "--path-style", "source-relative", "--include", "files" }, { text = true })
        :wait()
      if ret.code ~= 0 then
        return vim.notify("managed listing failed", vim.log.levels.ERROR, { title = "chezmoi" })
      end
      local files = vim.split(vim.trim(ret.stdout), "\n")
      vim.ui.select(files, { prompt = "chezmoi source files" }, function(choice)
        if choice then
          vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(src, choice)))
        end
      end)
    end,
  },
}

local ORDER = { "snacks", "telescope", "fzf-lua", "mini", "select" }

function M.open()
  local src = require("chezmoi-template.resolve").source_dir()
  if not src then
    return vim.notify("source directory not found", vim.log.levels.ERROR, { title = "chezmoi" })
  end
  local choice = require("chezmoi-template").config.picker
  if choice then
    local backend = backends[choice]
    if not backend then
      return vim.notify("unknown picker '" .. choice .. "'", vim.log.levels.ERROR, { title = "chezmoi" })
    end
    return backend.open(src)
  end
  for _, name in ipairs(ORDER) do
    if backends[name].avail() then
      return backends[name].open(src)
    end
  end
end

return M
