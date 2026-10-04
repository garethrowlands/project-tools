# Beat 2: Cmd+arrows hop focus round  slides | (A over (B | C)):
# slides → B (kitty picks the most recently focused of A and B) → C → A →
# slides. Each press must move focus.
slide goto 3 'Cmd+arrows'
focus deck
beat-pause 2
press-focus cmd+right
beat-pause 1.5
press-focus cmd+right
beat-pause 1.5
press-focus cmd+up
beat-pause 1.5
press-focus cmd+left
beat-pause 1.5
