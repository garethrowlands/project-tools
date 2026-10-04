# Beat 1: cards A and B give the tab some labelled panes, placed by kitty as
# it would place yours (B next to A); then the real Cmd+Shift+Enter opens C,
# a shell in the focused pane's directory, after B. In the tall layout: the
# slides on the left, A, B, C stacked on the right.
slide goto 2 'same directory'
card ensure A $'Pane A'
card ensure B $'Pane B' --next-to=id:${DEMO_IDS[A]}
beat-pause 2.5
focus B
press-new C cmd+shift+enter
type-text C 'clear; pwd\r'
beat-pause 3
