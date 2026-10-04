# Beat 5: clicks on words of the slide (presenterm ignores clicks), each left
# to ripple: the ripple bends the text around it. Then one click on empty
# background, below the slide's text, where only the faint glow shows a ring,
# as the slide says.
slide goto 7 'Clicks ripple'
mouse glide-text deck 'letters bend' 600
mouse click
beat-pause 1.2
mouse glide-text deck 'WAVE_SPEED' 600
mouse click
beat-pause 1.2
mouse glide-text deck 'pond-ripple' 600
mouse click
beat-pause 1.5
# empty background: well below the code block, away from the footer
mouse glide deck 70 75 800
mouse click
beat-pause 1.5
