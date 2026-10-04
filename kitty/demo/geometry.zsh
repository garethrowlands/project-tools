# Pure geometry for kitty/demo: turn a target inside a kitty pane into a
# screen point for Hammerspoon. No kitty or Hammerspoon calls, so it is unit
# tested with fixture JSON (tests/demo-tests.zsh).
#
# GEOM is the JSON demo_geometry.py writes, in framebuffer pixels:
#   {"os_windows": {"1": {"width": 1600, "height": 1000,
#                         "framebuffer_width": 3200, "framebuffer_height": 2000}},
#    "windows": {"5": {"os_window_id": 1, "left": 0, "top": 0, "right": 1600,
#                      "bottom": 2000, "columns": 40, "lines": 50}}}
# left/top/right/bottom bound the pane's cell area (padding excluded).
# FRAME is the OS window's frame in screen points from demoStage.frame(),
# title bar included: {"x": 100, "y": 50, "w": 1600, "h": 1028}. The content
# area is the bottom `height` points of it.

_demo_geom_jq='
  (.windows[$id] // error("no window")) as $w
  | (.os_windows[$w.os_window_id | tostring] // error("no os window")) as $o
  | ($o.width / $o.framebuffer_width) as $sx
  | ($o.height / $o.framebuffer_height) as $sy
  | def screen($px; $py):
      "\(($f.x + $px * $sx) | round) \(($f.y + $f.h - $o.height + $py * $sy) | round)";
'

# demo_point_in_pane GEOM FRAME ID XPCT YPCT -> "x y", XPCT/YPCT 0..100 of the pane.
demo_point_in_pane() {
  jq -r --arg id "$3" --argjson f "$2" --argjson xp "$4" --argjson yp "$5" "$_demo_geom_jq"'
    screen($w.left + ($w.right - $w.left) * $xp / 100;
           $w.top + ($w.bottom - $w.top) * $yp / 100)' <<<"$1" 2>/dev/null
}

# demo_point_at_cell GEOM FRAME ID ROW COL -> "x y", the centre of that cell
# (0-based row and column of the visible screen).
demo_point_at_cell() {
  jq -r --arg id "$3" --argjson f "$2" --argjson row "$4" --argjson col "$5" "$_demo_geom_jq"'
    screen($w.left + ($col + 0.5) * ($w.right - $w.left) / $w.columns;
           $w.top + ($row + 0.5) * ($w.bottom - $w.top) / $w.lines)' <<<"$1" 2>/dev/null
}

# demo_find_text TEXT LITERAL -> "row col" (0-based) of LITERAL's first
# occurrence in TEXT, one screen row per line; status 1 if it isn't there.
# Columns count characters, so wide characters (emoji, CJK) earlier on the
# row would put it off; the demo's scenes avoid them.
demo_find_text() {
  local -a rows=("${(@f)1}")
  local i prefix
  for (( i = 1; i <= $#rows; i++ )); do
    prefix=${rows[i]%%"$2"*}
    if [[ $prefix != "$rows[i]" ]]; then
      print -r -- "$(( i - 1 )) ${#prefix}"
      return 0
    fi
  done
  return 1
}
