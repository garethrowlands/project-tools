# Beat 6: Cmd+B opens blog's web page (its origin is this repo on GitHub) in
# Edge, tiled on the right half; then only that tab closes.
slide goto 10 'web page'
beat-pause 2
reveal 'Its GitHub or GitLab page' 2.5
reveal 'An open tab is reused' 2.5
reveal 'Watch: ⌘B on the blog pane' 3
stage tile-next com.microsoft.edgemac project-tools
press cmd+b
stage wait-tiled
beat-pause 3
stage close-tiled
beat-pause 1.5
