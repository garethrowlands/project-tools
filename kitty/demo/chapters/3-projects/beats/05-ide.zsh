# Beat 5: Cmd+I opens the focused pane's project (blog, from beat 4) in its
# IDE. Hammerspoon tiles VS Code on the right half as it appears, kitty on
# the left, then closes it and gives kitty the screen back.
slide goto 6 'Open the IDE'
beat-pause 4
stage tile-next com.microsoft.VSCode blog
press cmd+i
stage wait-tiled
beat-pause 3
stage close-tiled
beat-pause 1.5
