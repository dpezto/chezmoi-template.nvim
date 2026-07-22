#!/bin/sh
# Smoke test against a throwaway chezmoi setup that is deliberately unlike the
# author's: custom sourceDir, custom destDir, gpg (not age) encryption, and a
# second run with no chezmoi config at all. Requires chezmoi; gpg optional
# (encryption assertions are skipped without it). Never touches $HOME state.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

command -v chezmoi >/dev/null 2>&1 || { echo "smoke: chezmoi not found" >&2; exit 1; }

export XDG_CONFIG_HOME="$SCRATCH/config"
export XDG_DATA_HOME="$SCRATCH/data"
export GNUPGHOME="$SCRATCH/gnupg"
SRC="$SCRATCH/dotsrc"
DEST="$SCRATCH/home"
mkdir -p "$XDG_CONFIG_HOME/chezmoi" "$SRC/.chezmoitemplates" "$DEST"
mkdir -m 700 "$GNUPGHOME"

HAVE_GPG=0
if command -v gpg >/dev/null 2>&1; then
  HAVE_GPG=1
  gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
    --quick-gen-key 'chezmoi-smoke' default default never
fi

{
  printf 'sourceDir = "%s"\n' "$SRC"
  printf 'destDir = "%s"\n' "$DEST"
  if [ "$HAVE_GPG" = 1 ]; then
    printf 'encryption = "gpg"\n[gpg]\nrecipient = "chezmoi-smoke"\nargs = ["--quiet", "--batch", "--armor", "--trust-model", "always"]\n'
  fi
} > "$XDG_CONFIG_HOME/chezmoi/chezmoi.toml"

printf 'export SMOKE_OS={{ .chezmoi.os }}\n' > "$SRC/dot_zshrc.tmpl"
printf 'ignored-file\n' > "$SRC/.chezmoiignore"
printf '{{ .chezmoi.os }}\n' > "$SRC/.chezmoitemplates/oshelper"
if [ "$HAVE_GPG" = 1 ]; then
  printf 's3cret\n' | chezmoi encrypt > "$SRC/encrypted_dot_token.asc"
fi

echo "smoke: configured run (sourceDir=$SRC, gpg=$HAVE_GPG)"
cd "$ROOT"
CHEZMOI_SMOKE_SRC="$SRC" CHEZMOI_SMOKE_MODE=config \
  nvim --headless --clean -l tests/smoke.lua

echo "smoke: no-config run"
export XDG_CONFIG_HOME="$SCRATCH/emptycfg"
export XDG_DATA_HOME="$SCRATCH/emptydata"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME"
CHEZMOI_SMOKE_SRC="$SCRATCH" CHEZMOI_SMOKE_MODE=noconfig \
  nvim --headless --clean -l tests/smoke.lua

echo "smoke: all passed"
