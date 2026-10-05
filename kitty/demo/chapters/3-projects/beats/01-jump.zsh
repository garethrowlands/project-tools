# Beat 1: Cmd+§ opens switch-project over the tab; "shop" narrows it to the
# open shop-api project and Enter jumps to that tab. Ctrl+Shift+Tab (the
# previous tab) brings the slides back.
slide goto 2 'Jump to a project'
beat-pause 4
press cmd+§
adopt picker 'cmdline:"(^|/)switch-project$"'
wait-text picker 'Project> '
beat-pause 1.5
type-text picker 'shop'
beat-pause 1.5
press enter
wait-tab shop-api
beat-pause 2.5
press ctrl+shift+tab
wait-tab web-app
beat-pause 1
