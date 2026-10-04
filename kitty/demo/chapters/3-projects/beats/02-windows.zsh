# Beat 2: Option+Tab opens the window switcher: every window in this kitty,
# Claude Code panes labelled with their conversation title, the highlighted
# one previewed live. Two Downs move the highlight (rehearsal sets how many
# reach the Claude panes); Esc closes it where we were.
slide goto 3 'Every window, live'
beat-pause 4
press alt+tab
adopt switcher 'cmdline:(^|/)window$'
wait-text switcher 'ctrl-t: move to new tab'
beat-pause 2
press down
beat-pause 2
press down
beat-pause 2.5
press escape
wait-gone switcher
beat-pause 1
