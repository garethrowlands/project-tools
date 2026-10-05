# Beat 3: Cmd+Shift+W: tidy-windows asks Claude about every window (a real
# API call, hence the long wait) and pre-selects what it suggests; Enter
# applies it. Staged so the idle git log in docs is closed and the stray
# shop-api shell in "scratch" moves to shop-api's tab: both tabs leave the
# bar. If the model keeps docs-log, this beat fails: run the take again.
slide goto 6 'Tidy up'
adopt docs-log 'var:demo=docs-log'
adopt stray 'var:demo=stray'
beat-pause 2
reveal 'Claude reviews every window' 2.5
reveal 'Stale ones: close' 2
reveal 'Strays: back to their' 2.5
reveal 'Enter applies' 2.5
press cmd+shift+w
adopt tidy 'cmdline:"(^|/)tidy-windows$"'
DEMO_TIMEOUT=30 wait-text tidy 'enter: apply marked'
beat-pause 3
press enter
wait-gone docs-log
wait-in-tab stray shop-api
beat-pause 3
