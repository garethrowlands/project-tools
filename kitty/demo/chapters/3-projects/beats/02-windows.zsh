# Beat 2: Option+Tab opens the window switcher: every window in this kitty,
# Claude Code panes labelled with their conversation title. Typing "rate"
# filters on that title down to the shop-api Claude pane, previewed live;
# Esc closes it where we were.
slide goto 5 'Every window, live'
beat-pause 2
reveal 'Claude Code panes show their' 3
reveal 'Type to filter: titles count too' 2.5
reveal 'The preview is the live screen' 2.5
reveal 'Esc leaves you where you were' 2.5
press alt+tab
adopt switcher 'cmdline:"(^|/)window$"'
wait-text switcher 'ctrl-t: move to new tab'
beat-pause 2
type-text switcher 'rate'
wait-text switcher 'Add rate limiting'
beat-pause 3
press escape
wait-gone switcher
beat-pause 1
