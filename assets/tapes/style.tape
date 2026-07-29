# Shared look for every tape here, sourced instead of copied into each one:
#   Source assets/tapes/style.tape
# Paths are relative to the repo root, so run vhs from there.

Set FontFamily "FiraCode Nerd Font"
Set FontSize 18
Set Width 1300
Set Height 900
Set Theme "TokyoNight"
Set Margin 45
Set MarginFill "assets/tapes/backdrop.png"
Set WindowBar Colorful
Set WindowBarSize 36
Set BorderRadius 14
Set Padding 8
Set TypingSpeed 75ms
# nvim startup outlasts the 5s default, so Wait can cover it.
Set WaitTimeout 30s
