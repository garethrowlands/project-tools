# Beat 2: a new tab appears in the tab bar; focus moves to it (it glows),
# its card says we're going back, and focus returns to the slides' tab,
# which glows too. The deck changes slide while hidden, so it says so on
# return. C stays open in tab 2 for beat 7.
slide goto 3 'switch tabs'
beat-pause 1
card open C $'A whole new tab.\nIt glowed as we arrived.' --type=tab
beat-pause 1.5
focus C
beat-pause 2.5
card say C $'Now back to\nthe slides\' tab…'
beat-pause 1.5
slide goto 4 'and back again'
focus deck
beat-pause 2
pane close A
pane close B
beat-pause 1
