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

  if config.age.enabled then
    if config.age.engine == "chezmoi" then
      if vim.fn.executable("chezmoi") == 1 then
        health.ok("age engine: chezmoi (decrypt/encrypt delegated to chezmoi's encryption config)")
      else
        health.error("age engine is 'chezmoi' but the chezmoi executable is missing")
      end
    else
      local tool = require("chezmoi-template.age").tool()
      if vim.fn.executable(tool) == 1 then
        health.ok(("age engine: tool '%s'"):format(tool))
      else
        health.error(("age tool '%s' not found"):format(tool))
      end
    end
  end
end

return M
