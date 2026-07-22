# Recording the README GIFs

The tapes in `../tapes/` record against a **throwaway** chezmoi setup, so
recording never touches your real dotfiles. They reuse your local Neovim config
(symlinked in) so the GIFs match whatever colorscheme/plugins/font you already
run.

```sh
source assets/demo/setup.sh         # builds ~/.cache/chezmoi-template-demo, exports XDG_CONFIG_HOME
vhs assets/tapes/injection.tape     # -> assets/injection.gif
vhs assets/tapes/preview.tape
vhs assets/tapes/completion.tape
vhs assets/tapes/format.tape
vhs assets/tapes/picker.tape
```

## Prerequisites

- [`vhs`](https://github.com/charmbracelet/vhs) — records the tapes.
- `chezmoi` on `PATH` — the plugin resolves the target file through it.
- A Nerd Font — the tapes set `FontFamily "FiraCode Nerd Font"`; swap it in the
  `Set FontFamily` line of each tape if you use another.
- A local Neovim config providing a colorscheme (the tapes set
  `Theme "TokyoNight"` for the terminal chrome; buffer colors come from your
  config).
- Per-GIF extras:
  - `completion.gif` — a completion engine (blink.cmp or nvim-cmp).
  - `format.gif` — `conform.nvim` plus a shell formatter (`shfmt`) wired for
    `sh`/`zsh`; without it, only the template-directive depth-padding changes.

## How the harness works

`setup.sh` points `XDG_CONFIG_HOME` at a throwaway chezmoi config whose source
dir holds the demo template here, and symlinks your `~/.config/nvim` into the
throwaway XDG dir so the GIFs use your colorscheme/plugins/font. It leaves
`XDG_DATA_HOME` alone, so Neovim still loads plugins from your real data dir. The
throwaway `chezmoi.toml` defines `[data] is_lowmem = false` so the template's
custom variable renders and shows up in completion.

- **`dot_zshrc.tmpl`** — clean, valid; built-in `.chezmoi.*` data plus the
  `is_lowmem` demo variable. Drives all five shots: injection, preview,
  completion, picker, and format (`:%left` mangle, then format).

## Notes

- Every tape launches `nvim -i NONE --cmd 'luafile assets/demo/demo-init.lua'`.
  `-i NONE` skips shada, so no restored cursor position — each GIF opens the
  buffer at line 1. `demo-init.lua` sets `vim.g.chezmoi_demo=1` (an optional
  hook a config can read to hide recording noise — this config disables
  sidekick.nvim with it) and stubs `sidekick.status` so LazyVim's lualine
  components survive sidekick being off. Harmless no-op for configs that don't
  use either.
- **`injection.tape`** additionally sets the plugin's load guard
  (`vim.g.loaded_chezmoi_template=1`) so nothing auto-runs `setup()`. It then
  walks four highlighting setups in one window, each labelled in the winbar:
  (1) zsh regex, no treesitter — shell colors but `{{ }}` mangled, LSP errors;
  (2) gotmpl treesitter only — template structure colored, shell body plain;
  (3) zsh treesitter only — shell colored, `{{ }}` mangled, LSP errors;
  (4) `require('chezmoi-template').setup()` + `:e` — gotmpl + injected zsh,
  both correct, diagnostics clear.

Clean up when done: `rm -rf ~/.cache/chezmoi-template-demo`.
