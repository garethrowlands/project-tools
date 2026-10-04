# Beat 8: a second OS window; focus alternates so one window pulses amber
# while the other dims, cools and vignettes.
slide goto 9 'typing in?'
card open W $'I\'m a separate kitty window.' --type=os-window --os-window-title='kitty demo W'
stage place-beside 'kitty demo W'
focus W
card say W $'I\'m a separate kitty window.\nI have focus:\nan amber edge ✦'
beat-pause 2.5
focus deck
card say W $'Not focused:\ndimmer, cooler,\nshadowed edges.'
beat-pause 2.5
focus W
card say W $'Focus again:\nthe amber edge pulses.'
beat-pause 2.5
focus deck
card say W $'And back.'
beat-pause 2
pane close W
beat-pause 1
