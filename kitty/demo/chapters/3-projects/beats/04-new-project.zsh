# Beat 4: blog has no window yet: Cmd+§, "blog", Enter opens a shell there,
# in this tab beside the slides (switch-project's Enter launches a window in
# the current tab). It shows where it started.
slide goto 5 'no window'
beat-pause 4
press cmd+§
adopt picker 'cmdline:(^|/)switch-project$'
wait-text picker 'Project> '
type-text picker 'blog'
beat-pause 1.5
press-new blog enter
type-text blog "clear; pwd\r"
wait-text blog 'kitty-demo/blog'
beat-pause 3
