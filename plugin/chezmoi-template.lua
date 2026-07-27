-- Zero-config bootstrap: works without a setup() call. setup() is cheap — it
-- registers filetype detection, the treesitter directive, and light triggers,
-- deferring the heavy work until the first template opens or a :Chezmoi* command
-- runs. A later explicit setup({...}) (e.g. lazy.nvim `opts`) re-merges and wins:
-- options are read where they are used, not latched by this first registration.
if vim.g.loaded_chezmoi_template then
  return
end
vim.g.loaded_chezmoi_template = 1

local ct = require("chezmoi-template")
if not ct._did_setup then
  ct.setup(vim.g.chezmoi_template or {})
end
