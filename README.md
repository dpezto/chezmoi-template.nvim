# chezmoi-template.nvim

Edit your [chezmoi](https://chezmoi.io) source files **natively** — and make Neovim understand them.

Most chezmoi integrations wrap the `chezmoi edit` CLI: temporary buffers, watchers, apply-on-save. This plugin takes the opposite approach: you open the real source files (in `~/.local/share/chezmoi`, under git, with your normal workflow), and the editor becomes chezmoi-aware:

- **Real highlighting inside templates.** A `dot_zshrc.tmpl` is a `gotmpl` buffer whose text is treesitter-injected as **zsh** — Go-template syntax *and* target-language syntax, simultaneously. Works for any target language with a treesitter parser, resolved via `chezmoi target-path`. Includes `.chezmoitemplates/` partials, `.chezmoiignore` / `.chezmoiremove` / `.chezmoiexternal.*`.
- **Format templates as their target filetype** ([conform.nvim](https://github.com/stevearc/conform.nvim)). Go-template spans are masked with structurally inert placeholders, the buffer is formatted with the target filetype's formatter (shfmt, biome, taplo, …), then the spans are restored — with `{{ end }}` / `{{ else }}` re-indented to pair with their opener, and column-0 `{{-` directive blocks getting depth-encoding interior padding:

  ```
  {{- range $name, $spec := .packages.apps }}
  {{-   $roles := get $spec "role" }}
  {{-   if and $roleOK $osOK }}
  {{-     $via := get $spec "via" }}
  {{-   end }}
  {{- end }}
  ```
- **Target-aware icons** ([mini.icons](https://github.com/nvim-mini/mini.icons)). `private_dot_config/ghostty/config.tmpl` shows the ghostty icon, not a generic template glyph. Any combination of chezmoi source-state attributes (`private_`, `encrypted_`, `exact_`, `dot_`, `.tmpl`, `.age`, …) resolves to the deployed name.
- **Transparent encryption** (opt-in). chezmoi-managed `*.age` files decrypt on open and re-encrypt on save via `chezmoi decrypt` / `chezmoi encrypt` — whatever your chezmoi config uses (age, rage, builtin age, even gpg) just works. `encrypted_*.tmpl.age` still gets full template + target highlighting.
- **`%` matching for template delimiters** ([vim-matchup](https://github.com/andymass/vim-matchup)). `{{ if }}` ⇄ `{{ else }}` ⇄ `{{ end }}`, including `{{-` trim markers.
- **Live template preview.** `:ChezmoiPreview` renders the buffer through `chezmoi execute-template` into a split typed as the target filetype, re-rendered on every write.
- **Template diagnostics.** Errors from `chezmoi execute-template` surface as `vim.diagnostic` entries on write — template typos stop being invisible until apply fails.
- **Commands.** `:ChezmoiApply` (buffer target or `!` for all, optional apply-on-save), `:ChezmoiDiff`, `:ChezmoiTarget`, `:ChezmoiSource` (jump from a deployed file to its source; opt-in automatic redirect), `:ChezmoiPreview`.
- **Completion** ([blink.cmp](https://github.com/Saghen/blink.cmp)). Template data keys from `chezmoi data` (with value previews), template/sprig/chezmoi functions, and Go template keywords — only inside `{{ … }}`.

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

The plugin bootstraps itself with defaults — `setup()`/`opts` is only needed to change options. With other plugin managers, install and optionally set `vim.g.chezmoi_template = { ... }` before it loads.

## Configuration

Defaults:

```lua
require("chezmoi-template").setup({
  source_dir = nil,            -- nil = auto-detect via `chezmoi source-path`
  inject = { enabled = true }, -- treesitter injection of the target language
  format = {
    enabled = true,            -- conform formatter registration
    indent_directives = true,  -- depth-pad column-0 `{{-` directive blocks
  },
  icons  = { enabled = true }, -- mini.icons resolution (no-op if absent)
  commands = { enabled = true },
  apply = {
    on_save = false,           -- chezmoi apply <target> after writing a source file
    notify = true,
  },
  redirect = false,            -- opening a deployed managed file jumps to its source
  diagnostics = { enabled = true },
  age = {
    enabled = false,           -- opt-in
    engine = "chezmoi",        -- "chezmoi" (default) | "tool"
    -- engine = "tool" only:
    tool = nil,                -- nil = auto from chezmoi's config, fallback "age"
    identity = nil,            -- path or function; nil = auto from chezmoi's config
    recipients = nil,          -- list/string or function; nil = auto from chezmoi's config
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

### Encryption

Two engines:

- **`engine = "chezmoi"`** (default): decrypt/encrypt delegate to `chezmoi decrypt` / `chezmoi encrypt`. Identities, recipients, tool choice — even gpg — all come from chezmoi's own encryption config. Zero plugin config:

  ```lua
  age = { enabled = true, exclude = { "private%-keys" } },
  ```

- **`engine = "tool"`**: invoke an age-compatible binary directly (works without consulting chezmoi at edit time). `tool` defaults to chezmoi's configured `age.command` (fallback `age`); `identity` / `recipients` default to chezmoi's encryption config, or set them explicitly — values or functions:

  ```lua
  age = {
    enabled = true,
    engine = "tool",
    tool = "rage",
    identity = function()
      local host = vim.fn.hostname():gsub("%.local$", "")
      return "~/.config/chezmoi/" .. host .. "-key.txt"
    end,
    recipients = { "age1..." },
    exclude = { "private%-keys" }, -- e.g. passphrase-encrypted bootstrap keys
  },
  ```

## Completion

Register the blink.cmp source in your blink opts:

```lua
sources = {
  default = { "chezmoi", "lsp", "path", "buffer" },
  providers = {
    chezmoi = { name = "chezmoi", module = "chezmoi-template.blink" },
  },
}
```

It only activates inside `{{ … }}` in gotmpl buffers, so it stays out of the way of the target language's own completion. Note: templates using secret-manager functions (`onepassword`, `vault`, …) may make `:ChezmoiPreview`/diagnostics slow or fail without auth — those calls run whatever your template runs.

## vs. chezmoi.nvim / chezmoi.vim / the LazyVim extra

| | chezmoi.nvim + chezmoi.vim | chezmoi-template.nvim |
|---|---|---|
| Editing model | wraps `chezmoi edit` (tmp buffers, watch) | native source files |
| Template highlighting | regex compound filetypes (`sh.chezmoitmpl`) | treesitter injection of the real target language |
| Formatting | — | target-filetype formatting through templates |
| Icons | static per-extension glyphs | full source-name → target resolution |
| age files | — | transparent decrypt/encrypt (opt-in) |
| Preview / diagnostics | — | `:ChezmoiPreview`, template errors as diagnostics |
| Completion | — | data keys + template functions (blink.cmp) |
| Apply | apply-on-save via `chezmoi edit --watch` | `:ChezmoiApply`, opt-in apply-on-save |
| Picker | telescope/fzf/snacks picker | bring your own (composes with the extra's) |

## Health

`:checkhealth chezmoi-template` verifies the chezmoi binary, gotmpl parser, conform, and the encryption engine.

## Development

`make test` runs the formatter test suite headless (no external formatter binaries needed — conform is stubbed). CI runs it on stable and nightly Neovim.
