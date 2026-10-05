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
reveal 'Enter applies' 2.5
press cmd+shift+w
adopt tidy 'cmdline:"(^|/)tidy-windows$"'
DEMO_TIMEOUT=30 wait-text tidy 'enter: apply marked'
beat-pause 3
press enter
wait-any-gone docs-a docs-b
wait-in-tab stray shop-api
beat-pause 3
