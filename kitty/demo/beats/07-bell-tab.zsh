# Beat 7: C, in tab 2, rings: the whole tab area flashes and the tab title
# gets a bell. Then tab 2 goes.
slide goto 9 'another tab'
card ensure C $'A whole new tab —\nit glowed on arrival.' --type=tab
card say C $'I\'m in another tab.\nRinging in 3…'
beat-pause 1
card say C $'I\'m in another tab.\nRinging in 2…'
beat-pause 1
card say C $'I\'m in another tab.\nRinging in 1…'
beat-pause 1
bell C
beat-pause 2.5
pane close C
beat-pause 1
