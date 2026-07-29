# :Chezmoi pick — fuzzy-find over the source directory: entries labelled with
# their deployed target names (dot_zshrc.tmpl -> .zshrc), chezmoi internals
# hidden, preview with the target language injected.
# Run `source assets/demo/setup.sh` first (isolated demo source).
#   vhs assets/tapes/picker.tape

Output assets/picker.gif

Source assets/tapes/style.tape

Hide
# -n (no swapfile): recordings are throwaway, and a stale swap from an earlier
# session pops an "ignoring swapfile" notification over the shot.
Type "nvim -i NONE -n --cmd 'luafile assets/demo/demo-init.lua'" Enter
# No file argument, so there is no buffer text to wait on: hold for the dashboard.
Sleep 4s
Show
Type ":Chezmoi pick"
Sleep 500ms
Enter
Sleep 2s
Type "zsh"
Sleep 2s
Enter
Sleep 2.5s
Hide
Type ":qa!" Enter
