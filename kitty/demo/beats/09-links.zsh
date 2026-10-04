# Beat 9: eza and rg print hyperlinks; Cmd+click on the rg hit opens micro at
# that line, Cmd+click on a directory cds the shell. Needs kitty-cd-link.zsh
# in the interactive zsh (see kitty/ and the install-scripts skill).
slide goto 10 'land in a terminal app'
pane open A --location=vsplit --cwd=$DEMO_ROOT/scene/repo -- zsh -i
focus A
type-text A 'clear; eza --hyperlink -1; rg --hyperlink-format=kitty TODO\r'
wait-text A 'make it sparkle'
beat-pause 1.5
mouse glide-text A 'make it sparkle' 900
mouse click cmd
wait-window 'state:focused and cmdline:micro'
beat-pause 2.5
keys focused ctrl+q
wait-window 'state:focused and not cmdline:micro'
beat-pause 1
mouse glide-text A 'glitter' 900
mouse click cmd
# the cd shows only in the prompt, which varies; give it a moment, then prove it
beat-pause 1
type-text A 'eza -1\r'
wait-text A 'sparkle.txt'
beat-pause 2.5
focus deck
pane close A
