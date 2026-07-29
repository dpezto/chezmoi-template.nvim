# blink.cmp completion: data keys inside {{ }}, block snippet outside.
# Run `source assets/demo/setup.sh` first (isolated demo source).
#   vhs assets/tapes/completion.tape

Output assets/completion.gif

Source assets/tapes/style.tape

Hide
# -n (no swapfile): recordings are throwaway, and a stale swap from an earlier
# session pops an "ignoring swapfile" notification over the shot.
Type "nvim -i NONE -n --cmd 'luafile assets/demo/demo-init.lua' ~/.cache/chezmoi-template-demo/src/dot_zshrc.tmpl" Enter
Sleep 6s
Show
Type "G"
Sleep 300ms
Type "o"
Sleep 500ms
# inside an action: data keys with type icons + value docs
Type "{{ .chezmoi."
Sleep 2.5s
Type "os"
Sleep 2s
Escape
Sleep 300ms
Type "dd"
Sleep 500ms
# outside an action: block snippet expansion
Type "o"
Sleep 500ms
Type "if"
Sleep 2s
Enter
Sleep 2s
Escape
Hide
Type ":qa!" Enter
