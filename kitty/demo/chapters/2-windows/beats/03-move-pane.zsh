# Beat 3: Cmd+Shift+→ moves card A along the tab (it swaps with B), and
# Cmd+Shift+← moves it back. Starting with ← would swap A with the slides.
slide goto 4 'Move the pane itself'
focus A
beat-pause 2
press-reorders cmd+shift+right
beat-pause 1.5
press-reorders cmd+shift+left
beat-pause 1.5
