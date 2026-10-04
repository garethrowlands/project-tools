# Beat 7: detaching B (beat 6) made B's new tab active; it sits right after
# the slides' tab, but the window may hold other tabs too, so Ctrl+Shift+Tab
# (previous tab) gets back to the slides where Ctrl+Tab could wrap elsewhere.
# Then the slide, then Ctrl+Tab to B's tab and Ctrl+Shift+Tab back, ending on
# the slides for beat 8. Each arrival glows.
press-focus ctrl+shift+tab
beat-pause 1.5
slide goto 9 'Switch tabs'
beat-pause 2
press-focus ctrl+tab
beat-pause 2
press-focus ctrl+shift+tab
beat-pause 2
