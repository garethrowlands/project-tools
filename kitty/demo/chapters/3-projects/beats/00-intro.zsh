# Beat 0: the intro. The premise; the five tabs, listed and then visited for
# real (Ctrl+Tab is kitty's next tab, which wraps from the last tab back to
# the slides); then a map of the keys the rest of the chapter shows.
slide goto 1 'Getting around projects'
beat-pause 6
slide goto 2 'a tab per project'
beat-pause 8
for tab in shop-api infra docs scratch web-app; do
  press ctrl+tab
  wait-tab $tab
  [[ $tab == web-app ]] || beat-pause 2.5
done
beat-pause 1
slide goto 3 'Four ways around'
beat-pause 8
