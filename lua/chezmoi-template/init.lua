local M = {}

M.config = {
  -- nil = auto-detect via `chezmoi source-path`
  source_dir = nil,
  -- treesitter injection of the deployed target language into *.tmpl buffers
  inject = { enabled = true },
  -- conform.nvim formatter that formats templates as their target filetype
  format = {
    enabled = true,
    -- rewrite interior padding of whole-line `{{-` directives so template
    -- nesting depth reads as indentation: {{- lvl0 }}, {{-   lvl1 }}, …
    indent_directives = true,
  },
  -- resolve chezmoi source names to target icons in mini.icons
  icons = { enabled = true },
  -- transparent decrypt/encrypt of chezmoi-managed *.age files
  age = {
    enabled = false,
    -- "chezmoi": delegate to `chezmoi decrypt` / `chezmoi encrypt` — fully
    --   config-driven (age/rage/builtin/gpg, identities, recipients all come
    --   from chezmoi's own encryption config). Recommended.
    -- "tool": invoke an age-compatible binary directly (no chezmoi needed at
    --   encrypt/decrypt time); configured by the fields below.
    engine = "chezmoi",
    -- engine = "tool" only:
    tool = nil, -- nil = auto from `chezmoi dump-config` .age.command, fallback "age"
    identity = nil, -- path or function; nil = auto from chezmoi's encryption config
    recipients = nil, -- list/string or function; nil = auto from chezmoi's encryption config
    exclude = {}, -- lua patterns for *.age paths to leave untouched
  },
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- All *.tmpl files are gotmpl; the real target language is injected by
  -- treesitter (also avoids target-language LSPs choking on template syntax).
  vim.filetype.add({
    extension = { tmpl = "gotmpl" },
    filename = {
      [".chezmoiignore"] = "gitignore",
      [".chezmoiremove"] = "gitignore",
    },
  })

  if M.config.inject.enabled then
    require("chezmoi-template.inject").setup()
  end
  if M.config.format.enabled then
    require("chezmoi-template.format").setup()
  end
  if M.config.icons.enabled then
    require("chezmoi-template.icons").setup()
  end
  if M.config.age.enabled then
    require("chezmoi-template.age").setup()
  end
end

return M
