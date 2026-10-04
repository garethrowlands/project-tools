# Beat 8: one state per slide, each slide shown before the change it
# explains. kitty has focus (amber border); TextEdit, on a file that
# describes itself, takes it (kitty dims, tints, vignettes); focus returns
# (the border pulses). TextEdit opens in the background, hidden behind
# full-screen kitty until the tiling reveals it on the right half.
slide goto 10 'has focus?'
beat-pause 3.5
slide goto 11 'takes the focus'
stage open-other $DEMO_ROOT/scene/other-app.txt
stage tile-beside other-app.txt
stage focus-other other-app.txt
beat-pause 4
slide goto 12 'back to kitty'
stage focus-main
beat-pause 3.5
stage close-other other-app.txt
stage fill
beat-pause 1
