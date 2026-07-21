test:
	nvim --headless --clean -u tests/minimal_init.lua -l tests/run.lua

.PHONY: test
