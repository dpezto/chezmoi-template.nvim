# :Chezmoi preview — live rendered split, re-rendered as you type (no save).
# The pause after typing `{{` shows the stale mark: an in-progress (unclosed)
# action fails to render, so the last valid output is kept and flagged until the
# action is completed and it refreshes.
# Run `source assets/demo/setup.sh` first (isolated demo source).
#   vhs assets/tapes/preview.tape

Output assets/preview.gif

Source assets/tapes/style.tape

Hide
# -n (no swapfile): recordings are throwaway, and a stale swap from an earlier
# session pops an "ignoring swapfile" notification over the shot.
Type "nvim -i NONE -n --cmd 'luafile assets/demo/demo-init.lua' ~/.cache/chezmoi-template-demo/src/dot_zshrc.tmpl" Enter
Sleep 6s
Show
Type ":Chezmoi preview"
Sleep 500ms
Enter
Sleep 3s
# open an insert line on the blank line 2 — 'O' directly on the # comment line
# would inherit the comment leader (formatoptions 'o')
Type "gg"
Sleep 300ms
Type "j"
Sleep 300ms
Type "O"
Sleep 600ms
# type live — the preview updates on each idle pause, no :w needed.
# short line on purpose: the split is ~54 cols and 'sidescrolloff' would
# h-scroll the view for anything longer, clipping the left column
Type "export DEMO="
Sleep 500ms
# unclosed action — the render fails, preview freezes on the last valid output
# and the winbar shows the stale mark
Type "{{"
Sleep 1.2s
# complete the action — next render is valid, the mark clears and the right
# pane updates, still without saving
Type " .chezmoi.arch }}"
Sleep 1.5s
Escape
Sleep 800ms
# clean up the demo line — the preview live-refreshes back
Type "dd"
Sleep 1.2s
Type ":Chezmoi preview"
Sleep 500ms
Enter
Sleep 1s
Hide
Type ":qa!" Enter
