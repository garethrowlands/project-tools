# Beat 2: Cmd+arrows hop focus round the tall layout (slides left; A over B
# on the right), starting from B, where beat 1 left it (it was opened last):
# B → A → slides → A (kitty returns to the most recently focused pane on that
# side) → B. Focus moves only by keys; each press must move it.
slide goto 3 'Cmd+arrows'
beat-pause 2
press-focus cmd+up
beat-pause 1.5
press-focus cmd+left
beat-pause 1.5
press-focus cmd+right
beat-pause 1.5
press-focus cmd+down
beat-pause 1.5
