# Beat 3: B has focus (beat 2 ended there). Cmd+Shift+← moves it back one
# place (B and A swap, never touching the slides), then Cmd+Shift+→ moves it
# forward again; each move has its own slide, shown first.
slide goto 4 'Move the pane itself'
beat-pause 3
press-reorders cmd+shift+left
beat-pause 2
slide goto 5 'forward again'
beat-pause 2.5
press-reorders cmd+shift+right
beat-pause 2
