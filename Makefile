test:
	nvim --headless --clean -u tests/minimal_init.lua -l tests/run.lua

# Throwaway chezmoi config (custom sourceDir/destDir, gpg) + no-config run.
# Needs chezmoi on PATH; gpg optional. Not run in CI.
smoke:
	sh tests/smoke.sh

.PHONY: test smoke
