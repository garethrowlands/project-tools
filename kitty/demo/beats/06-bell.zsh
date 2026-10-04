# Beat 6: a pane counts down and rings while focus stays on the deck; only
# its edges flash.
slide goto 8 'pane rang?'
card open A 'Ringing in 3…' --location=vsplit
beat-pause 0.6
card say A 'Ringing in 2…'
beat-pause 0.6
card say A 'Ringing in 1…'
beat-pause 0.6
bell A
card say A $'Ding!\nOnly my edges flash —\nfocus never left the slides.'
beat-pause 2.5
pane close A
