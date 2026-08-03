# Changelog

## [3.0.0](https://github.com/dpezto/chezmoi-template.nvim/compare/v2.0.0...v3.0.0) (2026-08-03)


### ⚠ BREAKING CHANGES

* shared-template navigation, opt-in keymaps, preview diff ([#29](https://github.com/dpezto/chezmoi-template.nvim/issues/29))

### Features

* shared-template navigation, opt-in keymaps, preview diff ([#29](https://github.com/dpezto/chezmoi-template.nvim/issues/29)) ([be916f1](https://github.com/dpezto/chezmoi-template.nvim/commit/be916f150df24b80b018bde988e30a1e8e856c68))

## [2.0.0](https://github.com/dpezto/chezmoi-template.nvim/compare/v1.3.0...v2.0.0) (2026-07-27)


### ⚠ BREAKING CHANGES

* **picker:** decrypted previews; exclude patterns stack on the defaults ([#26](https://github.com/dpezto/chezmoi-template.nvim/issues/26))

### Features

* **picker:** decrypted previews; exclude patterns stack on the defaults ([#26](https://github.com/dpezto/chezmoi-template.nvim/issues/26)) ([db389a9](https://github.com/dpezto/chezmoi-template.nvim/commit/db389a9ad3a892ec77245c0a4b0686871cbdf919))


### Bug Fixes

* **apply:** skip undeployed source files, activate for deployed files on redirect ([#23](https://github.com/dpezto/chezmoi-template.nvim/issues/23)) ([5de7ae2](https://github.com/dpezto/chezmoi-template.nvim/commit/5de7ae2fa1803bab4bd8b88ee2ac8036b8d21dc0))
* **encryption:** read the enabled flag at dispatch, not at registration ([#25](https://github.com/dpezto/chezmoi-template.nvim/issues/25)) ([246de7f](https://github.com/dpezto/chezmoi-template.nvim/commit/246de7fe2e831a7bf67910eef6a9905c6ebd53bf))
* **matchup:** match else-with openers and full else chains ([#22](https://github.com/dpezto/chezmoi-template.nvim/issues/22)) ([ef43db1](https://github.com/dpezto/chezmoi-template.nvim/commit/ef43db10d289aa99817c7a64433993f084df59b2))

## [1.3.0](https://github.com/dpezto/chezmoi-template.nvim/compare/v1.2.0...v1.3.0) (2026-07-25)


### Features

* **apply:** report chezmoi's warnings when saving source state ([#19](https://github.com/dpezto/chezmoi-template.nvim/issues/19)) ([ed3adc6](https://github.com/dpezto/chezmoi-template.nvim/commit/ed3adc6fe3b1a440f7b424a19f842616adb4d2a4))


### Bug Fixes

* **activate:** bring up the plugin for managed files that are not templates ([#21](https://github.com/dpezto/chezmoi-template.nvim/issues/21)) ([dad3d9c](https://github.com/dpezto/chezmoi-template.nvim/commit/dad3d9cf63f56a27c762f5026d869f2e0a53fd51))
* **format:** mask key-position templates correctly, fall back for unmaskable lines ([#18](https://github.com/dpezto/chezmoi-template.nvim/issues/18)) ([c62b9fd](https://github.com/dpezto/chezmoi-template.nvim/commit/c62b9fddb2e91d392ce62a8e2f19fc04abb1da82))

## [1.2.0](https://github.com/dpezto/chezmoi-template.nvim/compare/v1.1.0...v1.2.0) (2026-07-23)


### Features

* **picker:** plugin-built entries with target names, excludes, injected previews ([#15](https://github.com/dpezto/chezmoi-template.nvim/issues/15)) ([2a48bf0](https://github.com/dpezto/chezmoi-template.nvim/commit/2a48bf0f727f25c99aaf387a27e5c3243b70ffd9))

## [1.1.0](https://github.com/dpezto/chezmoi-template.nvim/compare/v1.0.0...v1.1.0) (2026-07-23)


### Features

* close gaps vs chezmoi.nvim / chezmoi.vim ([#12](https://github.com/dpezto/chezmoi-template.nvim/issues/12)) ([312b7cb](https://github.com/dpezto/chezmoi-template.nvim/commit/312b7cbb0c56040e6878d693e96f2c10e8df2639))


### Bug Fixes

* harden path handling for Windows + add windows CI ([#13](https://github.com/dpezto/chezmoi-template.nvim/issues/13)) ([748a0d1](https://github.com/dpezto/chezmoi-template.nvim/commit/748a0d11d85036b359ebd4fd2e26c6074267d9c6))

## [1.0.0](https://github.com/dpezto/chezmoi-template.nvim/compare/v0.2.0...v1.0.0) (2026-07-22)


### ⚠ BREAKING CHANGES

* :Chezmoi <sub> commands + treesitter-aware blink completion ([#7](https://github.com/dpezto/chezmoi-template.nvim/issues/7))

### Features

* :Chezmoi &lt;sub&gt; commands + treesitter-aware blink completion ([#7](https://github.com/dpezto/chezmoi-template.nvim/issues/7)) ([a2ea342](https://github.com/dpezto/chezmoi-template.nvim/commit/a2ea34241cf4a80157fc6005e96f23898dd8fc49))

## [0.2.0](https://github.com/dpezto/chezmoi-template.nvim/compare/v0.1.0...v0.2.0) (2026-07-22)


### Features

* live real-time template preview ([c417334](https://github.com/dpezto/chezmoi-template.nvim/commit/c41733472de3042741d26f090e0ffe40d1c28e12))
