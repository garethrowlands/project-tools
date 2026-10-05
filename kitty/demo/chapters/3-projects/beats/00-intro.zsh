# Beat 0: the intro. The premise; the five tabs, listed and then visited for
# real (Ctrl+Tab is kitty's next tab, which wraps from the last tab back to
# the slides); then a map of the keys the rest of the chapter shows.
slide goto 1 'Getting around projects'
beat-pause 6
slide goto 2 'a tab per project'
beat-pause 2
reveal 'web-app: these slides' 2.5
reveal 'shop-api: Claude Code adding rate' 3.5
reveal 'infra: Claude Code moving' 3
reveal 'docs: two shells, untouched' 3
reveal 'scratch: a stray shop-api shell' 3
reveal "Let's look: ⌃⇥" 2.5
for tab in shop-api infra docs scratch web-app; do
  press ctrl+tab
  wait-tab $tab
  [[ $tab == web-app ]] || beat-pause 2.5
done
beat-pause 1
slide goto 3 'Four ways around'
beat-pause 2
reveal '⌘§ jump to a project' 2.5
reveal '⌥⇥ find any window' 3.5
reveal '⇧⌘W tidy up' 2.5
reveal '⌘I / ⌘B' 3
