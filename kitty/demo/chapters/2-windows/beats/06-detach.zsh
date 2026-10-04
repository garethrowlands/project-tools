# Beat 6: Cmd+Shift+↑ sends card B to a new tab.
slide goto 8 'own tab'
focus B
beat-pause 2
press cmd+shift+up
wait-own-tab B
beat-pause 2.5
