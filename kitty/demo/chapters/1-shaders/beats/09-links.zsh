# Beat 9: eza and rg print hyperlinks; one step per slide, each slide shown
# before its step. Cmd+click the rg hit's line number (rg links only the
# heading and the number) opens micro at that line; Cmd+click a directory in
# the eza listing cds the shell, and pwd plus the file there prove it. Needs
# kitty-cd-link.zsh in the interactive zsh (see kitty/ and install-scripts).
slide goto 13 'Clicking links in the terminal'
pane open A --location=vsplit --cwd=$DEMO_CHAPTER_DIR/scene/repo -- zsh -i
focus A
type-text A 'clear; eza --hyperlink -1; rg --hyperlink-format=kitty TODO\r'
wait-text A '5:# TODO'
beat-pause 3
slide goto 14 'search hit'
beat-pause 2
mouse glide-text A '5:# TODO' 900
mouse click cmd
wait-window 'state:focused and cmdline:micro'
beat-pause 2.5
keys focused ctrl+q
wait-window 'state:focused and not cmdline:micro'
slide goto 15 'a directory'
beat-pause 2
mouse glide-text A 'glitter' 900
mouse click cmd
# the cd shows only in the prompt, which varies; give it a moment, then prove it
beat-pause 1
type-text A 'pwd; cat sparkle.txt\r'
wait-text A 'clicking a directory link'
beat-pause 3.5
focus deck
pane close A
