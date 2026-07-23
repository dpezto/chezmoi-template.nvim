# :Chezmoi pick — fuzzy-find over the source directory: entries labelled with
# their deployed target names (dot_zshrc.tmpl -> .zshrc), chezmoi internals
# hidden, preview with the target language injected.
# Run `source assets/demo/setup.sh` first (isolated demo source).
#   vhs assets/tapes/picker.tape

Output assets/picker.gif

Set FontFamily "FiraCode Nerd Font"
Set FontSize 15
Set Width 1200
Set Height 640
Set Theme "TokyoNight"
Set Padding 12

Hide
Type "nvim -i NONE --cmd 'luafile assets/demo/demo-init.lua'" Enter
Sleep 4s
Show
Type ":Chezmoi pick"
Sleep 0.5s
Enter
Sleep 2s
Type "zsh"
Sleep 2s
Enter
Sleep 2.5s
Hide
Type ":qa!" Enter
