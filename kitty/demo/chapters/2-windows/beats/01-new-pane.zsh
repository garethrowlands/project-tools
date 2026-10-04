# Beat 1: the real Cmd+Shift+Enter, twice: from the slides it opens A (to
# the right, in the tall layout), from A it opens B (below A). Each new shell
# shows it started in the slides' directory and says which pane it is.
slide goto 2 'same directory'
beat-pause 2.5
press-new A cmd+shift+enter
type-text A "clear; pwd; echo 'This is pane A'\r"
wait-text A 'This is pane A'
beat-pause 2
press-new B cmd+shift+enter
type-text B "clear; pwd; echo 'This is pane B'\r"
wait-text B 'This is pane B'
beat-pause 2.5
