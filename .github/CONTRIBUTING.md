# Contributing

Thanks for helping out. Small, focused PRs merge fastest.

## Development

- `make test` — headless test suite (`tests/run.lua`). No external formatter binaries needed; conform is stubbed in `tests/minimal_init.lua`.
- `make smoke` — runs the plugin against a throwaway chezmoi setup (custom `sourceDir`/`destDir`, gpg encryption, and a no-config run). Needs `chezmoi` on `$PATH`, `gpg` optional. It never touches your real chezmoi state. Run this when you change anything in `resolve.lua`, `inject.lua`, or `encryption.lua`.
- `stylua lua plugin tests` before pushing — CI enforces `stylua --check`.

Add or extend a test for any behavior change. `tests/run.lua` is a plain assert-style runner — copy an existing case.

## Commits and PR titles

PRs are squash-merged, and releases are cut automatically by release-please from the commit history — so **PR titles must follow [Conventional Commits](https://www.conventionalcommits.org)** (`feat: …`, `fix: …`, `docs: …`, etc.). CI checks the title; `feat`/`fix` determine version bumps and CHANGELOG entries.

If your change touches the config surface or commands, update `README.md` and `doc/chezmoi-template.txt` in the same PR.

## AI-assisted contributions

AI assistance (Copilot, Claude, etc.) is welcome, with three rules:

1. **Disclose it** in the PR description (a one-liner is fine).
2. **You must understand and have tested the change yourself** — run `make test` (and `make smoke` where relevant) locally. You are the author; "the model wrote it" is not a review response.
3. **No unreviewed dumps.** Large AI-generated diffs with no accompanying reasoning, and AI-generated bug reports without a reproducible case, will be closed.

## Bug reports

Use the issue form. The `:checkhealth chezmoi-template` output and a minimal repro (a small chezmoi source dir layout + the file you opened) turn a week of back-and-forth into a same-day fix.
