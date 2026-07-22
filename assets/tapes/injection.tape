# Comparison shot: same chezmoi template, four highlighting setups in sequence.
#   1. zsh regex, no treesitter    — shell regex-colored, {{ }} mangled, LSP flags errors
#   2. gotmpl treesitter only      — template structure colored, shell body plain
#   3. zsh treesitter only         — shell colored by treesitter, {{ }} mangled, LSP errors
#   4. chezmoi-template.nvim       — gotmpl + injected zsh, both correct, no errors
# Launched with the plugin's load guard set (g:loaded_chezmoi_template=1) so nothing
# auto-runs setup(). Helpers S1..S4 are defined while hidden; each is a short visible
# toggle so the winbar-labelled state (and the lualine diagnostic count) is what changes.
# Run `source assets/demo/setup.sh` first (isolated demo source).
#   vhs assets/tapes/injection.tape   ->  assets/injection.gif

Output assets/injection.gif

Set FontFamily "FiraCode Nerd Font"
Set FontSize 15
Set Width 1200
Set Height 640
Set Theme "TokyoNight"
Set Padding 12

Hide
Type "nvim -i NONE --cmd 'luafile assets/demo/demo-init.lua' --cmd 'lua vim.g.loaded_chezmoi_template=1' ~/.cache/chezmoi-template-demo/src/dot_zshrc.tmpl" Enter
# treesitter-context throws on manual start/stop; disable it (pcall -> no-op if absent).
# Keep diagnostics ON but drop inline virtual_text: the lualine count still shows the
# LSP errors (the point in the ft=zsh stages), without spamming the buffer.
Type ":lua pcall(function() require('treesitter-context').disable() end)" Enter
Type ":lua pcall(vim.diagnostic.config, { virtual_text = false })" Enter
# Define the four states. Winbar labels each; the short S1..S4 calls read clearly.
Type ":lua S1=function() vim.cmd('set filetype=zsh'); pcall(vim.treesitter.stop,0); vim.wo.winbar='%=  ✗ no plugin — zsh regex, no treesitter  %=' end" Enter
# no explicit vim.treesitter.start: the FileType autocmd auto-starts it, and a
# second start() makes the decoration provider error out (all-white buffer)
Type ":lua S2=function() pcall(vim.treesitter.stop,0); vim.cmd('set filetype=gotmpl'); vim.wo.winbar='%=  ✗ no plugin — gotmpl treesitter (template only)  %=' end" Enter
Type ":lua S3=function() pcall(vim.treesitter.stop,0); vim.cmd('set filetype=zsh'); vim.wo.winbar='%=  ✗ no plugin — zsh treesitter (shell only)  %=' end" Enter
Type ":lua S4=function() require('chezmoi-template').setup(); vim.cmd('edit'); vim.wo.winbar='%=  ✓ chezmoi-template.nvim — gotmpl + zsh injection  %=' end" Enter
# Stage 1 set up while hidden; small pause lets the zsh LSP attach and publish before Show.
Type ":lua S1()" Enter
Show
# vhs compresses static holds ~0.4x, so these sleeps are ~2.5x the on-screen time.
Sleep 10s

# Stage 2 — gotmpl treesitter only: template structure colored, shell body plain.
Hide
Type ":lua S2()" Enter
Show
Sleep 10s

# Stage 3 — zsh treesitter only: shell colored by treesitter, {{ }} mangled, LSP errors.
Hide
Type ":lua S3()" Enter
Show
Sleep 10s

# Stage 4 — plugin on: gotmpl + injected zsh, both correct, diagnostics clear.
Hide
Type ":lua S4()" Enter
Show
Sleep 11s

Hide
Type ":qa!" Enter
