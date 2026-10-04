# Beat 3: micro on a file that narrates its own cursor jumps; the comet
# trail chases each one.
slide goto 4 'cursor go?'
pane open A --location=vsplit --cwd=$DEMO_ROOT/scene -- micro comet.txt
wait-text A 'The cursor starts here'
focus A
beat-pause 1.5
keys A end
beat-pause 1.5
keys A ctrl+end
beat-pause 1.5
keys A ctrl+home
beat-pause 1.5
keys A ctrl+f
type-text A 'search hit\r'
beat-pause 2
focus deck
pane close A
beat-pause 1
