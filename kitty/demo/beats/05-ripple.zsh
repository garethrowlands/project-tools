# Beat 5: clicks on words of the slide (presenterm ignores clicks), each left
# to ripple. The ripple only bends text that is there, so every click aims
# at text: on empty background it would be invisible.
slide goto 6 'Clicks ripple'
mouse glide-text deck 'letters bend' 600
mouse click
beat-pause 1.2
mouse glide-text deck 'WAVE_SPEED' 600
mouse click
beat-pause 1.2
mouse glide-text deck 'pond-ripple' 600
mouse click
beat-pause 1.5
