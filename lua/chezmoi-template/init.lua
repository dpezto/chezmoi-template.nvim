local M = {}

M.config = {
  -- nil = auto-detect via `chezmoi source-path`
  source_dir = nil,
  -- treesitter injection of the deployed target language into *.tmpl buffers
  inject = { enabled = true },
  -- conform.nvim formatter that formats templates as their target filetype
  format = {
    enabled = true,
    -- rewrite interior padding of column-0 `{{-` directives so template
    -- nesting depth reads as indentation: {{- lvl0 }}, {{-   lvl1 }}, …
    indent_directives = true,
  },
  -- resolve chezmoi source names to target icons in mini.icons
  icons = { enabled = true },
  -- :ChezmoiApply / :ChezmoiDiff / :ChezmoiTarget / :ChezmoiSource / :ChezmoiPreview
  commands = { enabled = true },
  -- run `chezmoi apply <target>` after writing a managed source file
  apply = { on_save = false, notify = true },
  -- opening a deployed managed file jumps to its chezmoi source (opt-in)
  redirect = false,
  -- surface template errors (via `chezmoi execute-template`) as diagnostics on write
  diagnostics = { enabled = true },
  -- transparent decrypt/encrypt of chezmoi-managed encrypted files (*.age, *.asc)
  encryption = {
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

-- Every augroup the plugin can own. Cleared unconditionally on setup() so
-- re-running with a feature turned off removes its autocmds (setup is
-- re-runnable: the plugin/ bootstrap may run it before the user's call).
local GROUPS = { "tmpl", "templates", "encryption", "format", "icons", "commands", "diagnostics" }

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  M._did_setup = true

  for _, g in ipairs(GROUPS) do
    vim.api.nvim_create_augroup("chezmoi-template." .. g, { clear = true })
  end

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
  if M.config.encryption.enabled then
    require("chezmoi-template.encryption").setup()
  end
  require("chezmoi-template.commands").setup()
  if M.config.diagnostics.enabled then
    require("chezmoi-template.diagnostics").setup()
  end
end

return M
