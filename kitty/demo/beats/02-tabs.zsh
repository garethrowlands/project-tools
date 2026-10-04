# Beat 2: a new tab glows on arrival; back to the deck's tab. C stays open
# in tab 2 for beat 7.
slide goto 3 'switch tabs'
beat-pause 1
card open C $'A whole new tab —\nit glowed on arrival.' --type=tab
focus C
beat-pause 2.5
focus deck
pane close A
pane close B
beat-pause 1.5
