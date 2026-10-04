# Beat 8: another app (TextEdit, on a file that describes itself) takes
# focus; the screen tiles, kitty on the left half. kitty steps back (dimmer,
# cool tint, vignette) while TextEdit has focus and glows amber when focus
# returns. Then TextEdit's window closes and kitty fills the screen again.
slide goto 10 'has focus?'
stage open-other $DEMO_ROOT/scene/other-app.txt
stage tile-beside other-app.txt
beat-pause 3
stage focus-main
beat-pause 2.5
stage focus-other other-app.txt
beat-pause 2.5
stage focus-main
beat-pause 2
stage close-other other-app.txt
stage fill
beat-pause 1
