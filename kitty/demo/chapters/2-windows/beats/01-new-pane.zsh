# Beat 1: cards A and B give the tab some labelled panes; then the real
# Cmd+Shift+Enter opens C, a shell in the slides' directory.
slide goto 2 'same directory'
card ensure A $'Pane A' --location=vsplit
card ensure B $'Pane B' --location=hsplit --next-to=id:${DEMO_IDS[A]}
beat-pause 2.5
press-new C cmd+shift+enter
type-text C 'clear; pwd\r'
beat-pause 3
