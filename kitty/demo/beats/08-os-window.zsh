# Beat 8: one state per slide, each slide shown before the change it
# explains. kitty has focus (amber border); TextEdit, on a file that
# describes itself, takes it (kitty dims, tints, vignettes); focus returns
# (the border pulses). kitty makes room first (left half); Hammerspoon puts
# TextEdit's window on the right half the moment it appears.
slide goto 10 'has focus?'
beat-pause 3.5
slide goto 11 'takes the focus'
stage open-other $DEMO_ROOT/scene/other-app.txt
beat-pause 4
slide goto 12 'back to kitty'
stage focus-main
beat-pause 3.5
stage close-other other-app.txt
stage fill
beat-pause 1
