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

  -- blink completion docs are fenced code blocks; without markdown_inline they
  -- render as literal ``` and the value's type isn't highlighted
  if pcall(vim.treesitter.language.add, "markdown_inline") then
    health.ok("markdown_inline parser installed (highlighted completion docs)")
  else
    health.warn(
      "markdown_inline treesitter parser missing",
      "blink.cmp completion docs show raw ``` fences; install it, e.g. :TSInstall markdown markdown_inline"
    )
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
    if vim.fn.executable("chezmoi") == 1 then
      health.ok("encryption enabled (decrypt/encrypt delegated to chezmoi's encryption config)")
    else
      health.error("encryption is enabled but the chezmoi executable is missing")
    end
  end
end

return M
