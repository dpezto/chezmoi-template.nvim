local M = {}

function M.check()
  local health = vim.health
  health.start("chezmoi-template")

  if vim.fn.executable("chezmoi") == 1 then
    health.ok("chezmoi executable found")
  else
    health.warn(
      "chezmoi executable not found",
      "Target-language detection is disabled; *.tmpl files get plain gotmpl highlighting only"
    )
  end

  if pcall(vim.treesitter.language.add, "gotmpl") then
    health.ok("gotmpl treesitter parser installed")
  else
    health.error("gotmpl treesitter parser missing", "Install it, e.g. via nvim-treesitter: :TSInstall gotmpl")
  end

  local config = require("chezmoi-template").config

  if config.format.enabled then
    if pcall(require, "conform") then
      health.ok("conform.nvim found; chezmoi formatter registered")
    else
      health.warn("conform.nvim not found; template formatting disabled")
    end
  end

  if config.encryption.enabled then
    if config.encryption.engine == "chezmoi" then
      if vim.fn.executable("chezmoi") == 1 then
        health.ok("encryption engine: chezmoi (decrypt/encrypt delegated to chezmoi's encryption config)")
      else
        health.error("encryption engine is 'chezmoi' but the chezmoi executable is missing")
      end
    else
      local tool = require("chezmoi-template.encryption").tool()
      if vim.fn.executable(tool) == 1 then
        health.ok(("encryption engine: tool '%s'"):format(tool))
      else
        health.error(("encryption tool '%s' not found"):format(tool))
      end
    end
  end
end

return M
