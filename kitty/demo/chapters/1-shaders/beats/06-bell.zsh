# Beat 6: a pane counts down and rings while focus stays on the deck; only
# its edges flash and its text shakes, and the edges stay lit.
slide goto 8 'pane rang?'
card open A 'Ringing in 3…' --location=vsplit
beat-pause 0.6
card say A 'Ringing in 2…'
beat-pause 0.6
card say A 'Ringing in 1…'
beat-pause 0.6
bell A
card say A $'Ding!\nMy edges flash and my text\nshakes; they stay lit till\nyou focus me.'
beat-pause 2.5
pane close A
