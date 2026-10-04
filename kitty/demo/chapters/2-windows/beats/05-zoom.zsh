# Beat 5: Ctrl+Option+Z zooms the focused pane to the whole tab and back.
slide goto 6 'Zoom one pane'
beat-pause 2
press ctrl+alt+z
wait-layout stack
beat-pause 2
press ctrl+alt+z
wait-layout grid
beat-pause 1.5
