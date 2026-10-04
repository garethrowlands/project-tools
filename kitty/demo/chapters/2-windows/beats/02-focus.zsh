# Beat 2: Cmd+arrows hop focus round the tall layout (slides left; A over B
# on the right): slides → B (kitty picks the most recently focused pane on
# the right) → A → slides. Each press must move focus.
slide goto 3 'Cmd+arrows'
focus deck
beat-pause 2
press-focus cmd+right
beat-pause 1.5
press-focus cmd+up
beat-pause 1.5
press-focus cmd+left
beat-pause 1.5
