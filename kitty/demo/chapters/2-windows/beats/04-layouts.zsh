# Beat 4: the four layouts, starting from tall and ending back on it, so
# beat 5's zoom shows and returns to tall.
slide goto 5 'Layouts'
beat-pause 2.5
press cmd+f
wait-layout fat
beat-pause 2
press cmd+g
wait-layout grid
beat-pause 2
press cmd+s
wait-layout stack
beat-pause 2
press cmd+t
wait-layout tall
beat-pause 2
