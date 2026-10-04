# Beat 7: detaching B (beat 6) made B's tab active, so first Ctrl+Tab back to
# the slides; then the slide, then Ctrl+Tab to B's tab and Ctrl+Shift+Tab back,
# ending on the slides for beat 8. Each arrival glows.
press-focus ctrl+tab
beat-pause 1.5
slide goto 8 'Switch tabs'
beat-pause 2
press-focus ctrl+tab
beat-pause 2
press-focus ctrl+shift+tab
beat-pause 2
