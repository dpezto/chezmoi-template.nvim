#!/bin/bash
# Build a throwaway chezmoi setup for recording the README GIFs, so recording
# never touches your real dotfiles or leaks your real chezmoi data. Your real
# Neovim config is kept (symlinked in) so the GIFs use your colorscheme/plugins.
#
# Usage:  source assets/demo/setup.sh   (source, not run — it exports an env var)
#         vhs assets/tapes/preview.tape
#
# Every `chezmoi` subcommand honors XDG_CONFIG_HOME, so pointing it at $ROOT/xdg
# makes chezmoi use $ROOT/src as its source. XDG_DATA_HOME is left alone, so
# Neovim still loads plugins from your real data dir.
set -eu

_demo_dir=$(cd "$(dirname "${BASH_SOURCE:-$0}")" && pwd)
ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/chezmoi-template-demo"
rm -rf "$ROOT/src" # drop stale templates from previous runs (the picker lists them)
mkdir -p "$ROOT/xdg/chezmoi" "$ROOT/src" "$ROOT/home"

# keep the real Neovim config (colorscheme, blink, conform, font)
ln -sfn "${XDG_CONFIG_HOME:-$HOME/.config}/nvim" "$ROOT/xdg/nvim"

printf 'sourceDir = "%s/src"\ndestDir = "%s/home"\n[data]\nis_lowmem = false\n[data.packages.apps.nvim]\nrole = "core"\nvia = "brew"\n' "$ROOT" "$ROOT" \
  > "$ROOT/xdg/chezmoi/chezmoi.toml"

cp "$_demo_dir/dot_zshrc.tmpl" "$ROOT/src/"

export XDG_CONFIG_HOME="$ROOT/xdg"
echo "Demo source ready: $ROOT/src"
echo "XDG_CONFIG_HOME now points at the throwaway config for this shell."
echo "Record with:  vhs assets/tapes/<name>.tape"
echo "(If vhs doesn't inherit it, add:  Env XDG_CONFIG_HOME \"$ROOT/xdg\"  to the tape.)"
