# chezmoi-template.nvim

Edit your [chezmoi](https://chezmoi.io) source files **natively** — and make Neovim understand them.

Most chezmoi integrations wrap the `chezmoi edit` CLI: temporary buffers, watchers, apply-on-save. This plugin takes the opposite approach: you open the real source files (in `~/.local/share/chezmoi`, under git, with your normal workflow), and the editor becomes chezmoi-aware:

- **Real highlighting inside templates.** A `dot_zshrc.tmpl` is a `gotmpl` buffer whose text is treesitter-injected as **zsh** — Go-template syntax *and* target-language syntax, simultaneously. Works for any target language with a treesitter parser, resolved via `chezmoi target-path`. Includes `.chezmoitemplates/` partials, `.chezmoiignore` / `.chezmoiremove` / `.chezmoiexternal.*`.
- **Format templates as their target filetype** ([conform.nvim](https://github.com/stevearc/conform.nvim)). Go-template spans are masked with structurally inert placeholders, the buffer is formatted with the target filetype's formatter (shfmt, biome, taplo, …), then the spans are restored — with `{{ end }}` / `{{ else }}` re-indented to pair with their opener.
- **Target-aware icons** ([mini.icons](https://github.com/nvim-mini/mini.icons)). `private_dot_config/ghostty/config.tmpl` shows the ghostty icon, not a generic template glyph. Any combination of chezmoi source-state attributes (`private_`, `encrypted_`, `exact_`, `dot_`, `.tmpl`, `.age`, …) resolves to the deployed name.
- **Transparent age encryption** (opt-in). chezmoi-managed `*.age` files decrypt on open and re-encrypt on save, using identities/recipients from your chezmoi config (or your own). `encrypted_*.tmpl.age` still gets full template + target highlighting.
- **`%` matching for template delimiters** ([vim-matchup](https://github.com/andymass/vim-matchup)). `{{ if }}` ⇄ `{{ else }}` ⇄ `{{ end }}`, including `{{-` trim markers.

Everything degrades gracefully: without the `chezmoi` binary you keep plain gotmpl highlighting and nothing errors.

## Requirements

- Neovim ≥ 0.10
- `chezmoi` on `$PATH` (optional, but the point)
- nvim-treesitter with the `gotmpl` parser (plus parsers for your target languages)
- Optional: [conform.nvim](https://github.com/stevearc/conform.nvim) (formatting), [mini.icons](https://github.com/nvim-mini/mini.icons) (icons), [vim-matchup](https://github.com/andymass/vim-matchup) (`%` matching), `rage` or `age` (encryption)

## Installation

lazy.nvim:

```lua
{
  "dpezto/chezmoi-template.nvim",
  -- filetype + BufReadPre autocmds must exist before the first file opens
  lazy = false,
  opts = {},
}
```

## Configuration

Defaults:

```lua
require("chezmoi-template").setup({
  source_dir = nil,            -- nil = auto-detect via `chezmoi source-path`
  inject = { enabled = true }, -- treesitter injection of the target language
  format = { enabled = true }, -- conform formatter registration
  icons  = { enabled = true }, -- mini.icons resolution (no-op if absent)
  age = {
    enabled = false,           -- opt-in
    tool = "rage",             -- or "age"
    identity = nil,            -- path or function; default: chezmoi's encryption config
    recipients = nil,          -- list/string or function; default: chezmoi's encryption config
    exclude = {},              -- lua patterns for *.age paths to leave untouched
  },
})
```

### Formatting

The formatter is registered with conform as `chezmoi`, and `formatters_by_ft.gotmpl = { "chezmoi" }` is set if you haven't set it yourself. It formats using the **target filetype's** formatter, so that formatter must be installed and configured in conform as usual.

If you use the age module and format decrypted `*.age` buffers, route them through the `chezmoi` formatter too (it strips the `.age` suffix before handing the file to the underlying formatter):

```lua
-- in your conform opts, after defining formatters_by_ft
for ft, formatters in pairs(opts.formatters_by_ft) do
  if type(formatters) == "table" then
    opts.formatters_by_ft[ft] = function(bufnr)
      return vim.api.nvim_buf_get_name(bufnr):match("%.age$") and { "chezmoi" } or formatters
    end
  end
end
```

### Icons

mini.icons has no resolver hook, so the integration wraps `MiniIcons.get()` (transparently for non-chezmoi names). If you lazy-load mini.icons and icons don't resolve, call the attach explicitly from its `config`:

```lua
require("chezmoi-template.icons").attach()
```

For statusline/bufferline components, `require("chezmoi-template.icons").get(path)` returns the target's `glyph, hl` (or nil for non-chezmoi paths). lualine example:

```lua
local function file_icon()
  local icon, hl = require("chezmoi-template.icons").get(vim.api.nvim_buf_get_name(0))
  if not icon then
    return ""
  end
  return icon
end
```

### Age encryption

With no explicit `identity` / `recipients`, both are read from chezmoi's own `[age]` encryption config (`chezmoi dump-config`). Override either with a value or a function, e.g. per-host key files:

```lua
age = {
  enabled = true,
  identity = function()
    local host = vim.fn.hostname():gsub("%.local$", "")
    return "~/.config/chezmoi/" .. host .. "-key.txt"
  end,
  recipients = function()
    local out = vim.system(
      { "chezmoi", "execute-template", "{{ range .age.recipients }}{{ . }}\n{{ end }}" },
      { text = true }
    ):wait()
    return vim.split(vim.trim(out.stdout), "\n")
  end,
  exclude = { "private%-keys" }, -- e.g. passphrase-encrypted bootstrap keys
},
```

## vs. chezmoi.nvim / chezmoi.vim / the LazyVim extra

| | chezmoi.nvim + chezmoi.vim | chezmoi-template.nvim |
|---|---|---|
| Editing model | wraps `chezmoi edit` (tmp buffers, watch) | native source files |
| Template highlighting | regex compound filetypes (`sh.chezmoitmpl`) | treesitter injection of the real target language |
| Formatting | — | target-filetype formatting through templates |
| Icons | static per-extension glyphs | full source-name → target resolution |
| age files | — | transparent decrypt/encrypt (opt-in) |
| Picker / apply-on-save | yes | no — bring your own picker; `chezmoi apply` when you choose |

They compose: keep the LazyVim `util.chezmoi` extra for its picker and add this plugin for everything else.

## Health

`:checkhealth chezmoi-template` verifies the chezmoi binary, gotmpl parser, conform, and the age tool.
