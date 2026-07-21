-- Zero-config bootstrap: works without a setup() call. A later explicit
-- setup({...}) (e.g. lazy.nvim `opts`) re-runs cleanly and wins.
if vim.g.loaded_chezmoi_template then
  return
end
vim.g.loaded_chezmoi_template = 1

local ct = require("chezmoi-template")
if not ct._did_setup then
  ct.setup(vim.g.chezmoi_template or {})
end
