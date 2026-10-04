# Beat 1: cards A and B give the tab some labelled panes; then the real
# Cmd+Shift+Enter opens C, a shell in the directory of the focused pane. B
# is focused first so C splits B, not the slides: the slides keep half the
# screen and the tab is  slides | (A over (B | C)).
slide goto 2 'same directory'
card ensure A $'Pane A' --location=vsplit
card ensure B $'Pane B' --location=hsplit --next-to=id:${DEMO_IDS[A]}
beat-pause 2.5
focus B
press-new C cmd+shift+enter
type-text C 'clear; pwd\r'
beat-pause 3
