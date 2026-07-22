# :ChezmoiPreview — live rendered split, re-rendered on write.
# Run `source assets/demo/setup.sh` first (isolated demo source).
#   vhs assets/tapes/preview.tape

Output assets/preview.gif

Set FontFamily "FiraCode Nerd Font"
Set FontSize 15
Set Width 1200
Set Height 640
Set Theme "TokyoNight"
Set Padding 12
Set TypingSpeed 75ms

Hide
Type "nvim -i NONE --cmd 'luafile assets/demo/demo-init.lua' ~/.cache/chezmoi-template-demo/src/dot_zshrc.tmpl" Enter
Sleep 6s
Show
Type ":ChezmoiPreview" Enter
Sleep 3s
# make a small edit and write — the preview re-renders
Type "gg"
Sleep 300ms
# open the line on the blank line 2 — 'O' directly on the # comment line
# would inherit the comment leader (formatoptions 'o')
Type "j"
Sleep 300ms
Type "O"
Sleep 800ms
# short line on purpose: the split is ~54 cols and 'sidescrolloff' would
# h-scroll the view for anything longer, clipping the left column
Type `export DEMO={{ .chezmoi.arch }}`
Sleep 800ms
Escape
Sleep 500ms
Type ":w" Enter
Sleep 3s
# clean up the demo line
Type "dd"
Sleep 500ms
Type ":w" Enter
Sleep 2s
Type ":ChezmoiPreview" Enter
Sleep 1s
Hide
Type ":qa!" Enter
