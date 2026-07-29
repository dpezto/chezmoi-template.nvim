# Format-through-template: conform formats as the target filetype (needs a
# shell formatter, e.g. shfmt, configured in conform for sh/zsh), then the
# chezmoi formatter re-pairs {{ end }}/{{ else }} and depth-pads {{- directives.
# Run `source assets/demo/setup.sh` first (isolated demo source).
#   vhs assets/tapes/format.tape

Output assets/format.gif

Source assets/tapes/style.tape

Hide
# -n (no swapfile): recordings are throwaway, and a stale swap from an earlier
# session pops an "ignoring swapfile" notification over the shot.
Type "nvim -i NONE -n --cmd 'luafile assets/demo/demo-init.lua' ~/.cache/chezmoi-template-demo/src/dot_zshrc.tmpl" Enter
Sleep 6s
Show
Sleep 1.5s
# mangle: flatten every line to column 0
Type ":%left"
Sleep 1.25s
Enter
Sleep 2s
# format: shell re-indents, template directives re-pair + depth-pad
Type ":lua require('conform').format()"
Sleep 1.25s
Enter
Sleep 3s
Hide
Type ":qa!" Enter
