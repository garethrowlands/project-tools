# Beat 3: Cmd+Shift+W: tidy-windows asks Claude about every window (a real
# API call, hence the long wait) and pre-selects what it suggests; Enter
# applies it. Staged to suit its rules: docs' two idle shells (a clean,
# pushed repo, untouched for six weeks) are duplicates, so it closes one or
# both; shop-api's tree is dirty, so its shells are kept and the stray one
# in "scratch" moves to shop-api's tab. If the model keeps both docs
# shells, this beat fails: run the take again.
slide goto 6 'Tidy up'
adopt docs-a 'var:demo=docs-a'
adopt docs-b 'var:demo=docs-b'
adopt stray 'var:demo=stray'
beat-pause 2
reveal 'Claude reviews every window' 2.5
reveal 'Stale ones: close' 2
reveal 'Strays: back to their' 2.5
reveal '↩ applies' 2.5
reveal 'Watch: ⇧⌘W, then ↩' 3
press cmd+shift+w
adopt tidy 'cmdline:"(^|/)tidy-windows$"'
DEMO_TIMEOUT=30 wait-text tidy 'enter: apply marked'
# time to read the pre-selected rows
beat-pause 5
press enter
wait-any-gone docs-a docs-b
wait-in-tab stray shop-api
beat-pause 1
# tidy-windows exits quietly once applied, and its changes are in other
# tabs: show them, as the intro showed them before
slide goto 7 'After the tidy-up'
beat-pause 2
reveal 'The stray shop-api shell' 3
reveal 'docs is down to one shell' 3
reveal 'Watch: ⌃⇥, tab by tab' 3
tour-tabs
beat-pause 1
