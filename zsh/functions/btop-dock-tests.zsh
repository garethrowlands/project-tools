#!/usr/bin/env zsh
# Tests for bin/btop-dock against a fake `kitten` that records its arguments and
# answers `@ ls` from $FAKE_LS.

_pass() { print "PASS: $1" }
_fail() { print "FAIL: $1"; (( _failures++ )) }
_assert_contains() { [[ "$1" == *"$2"* ]] && _pass "$3" || _fail "$3: $(printf '%q' "$1") does not contain $(printf '%q' "$2")" }
_assert_not_contains() { [[ "$1" != *"$2"* ]] && _pass "$3" || _fail "$3: output unexpectedly contains $(printf '%q' "$2")" }

integer _failures=0
_bd=${0:A:h}/../bin/btop-dock
_zt=$(mktemp -d "${TMPDIR:-/tmp}/btop-dock-test-XXXXXX"); _zt=${_zt:A}
mkdir -p "$_zt/bin" "$_zt/home/.config/btop"
print -r -- 'color_theme = "catppuccin"
shown_boxes = "cpu mem net proc"
update_ms = 2000' > "$_zt/home/.config/btop/btop.conf"
_conf="$_zt/home/.cache/project-tools/btop-dock.conf"
print -r -- '#!/bin/zsh
print -r -- "kitten ${(j: :)${(q)@}}" >> '$_zt'/calls
if [[ "$2" == ls ]]; then print -r -- "$FAKE_LS"; fi
if [[ "$2" == launch ]]; then print 42; fi' > "$_zt/bin/kitten"
chmod +x "$_zt/bin/kitten"

# runs btop-dock; prints the calls made, then its output and rc=N.
# zsh -f: the user's ~/.zshenv would put the real kitten first on PATH; no listen
# socket either, so nothing can reach a live kitty
_run() {
  : > "$_zt/calls"
  local out rc
  out=$(HOME="$_zt/home" XDG_CONFIG_HOME= XDG_CACHE_HOME= KITTY_LISTEN_ON= PATH="$_zt/bin:$PATH" zsh -f "$_bd" "$@" 2>&1); rc=$?
  cat "$_zt/calls"; print -r -- "$out"; print "rc=$rc"
}
# two tabs: window 7 is in tab "a"; window 8 in tab "b", which also has a btop window 31
export FAKE_LS='[{"tabs":[
  {"id":1,"title":"a","windows":[{"id":7,"title":"claude"}]},
  {"id":2,"title":"b","windows":[{"id":8,"title":"claude"},{"id":31,"title":"btop"}]}]}]'
unset BTOP_DOCK_SIZE BTOP_DOCK_EDGE
export KITTY_WINDOW_ID=7

out=$(_run)
_assert_contains "$out" "kitten @ launch --type=tab-dock --dock-edge=bottom --dock-size=25% --dock-skip-focus --match=window_id:7 --title=btop btop -c $_conf" \
  "open: a bottom tab-dock on the caller's tab, never focused"
_assert_contains "$out" "42" "open: prints the new window's id"

out=$(KITTY_WINDOW_ID= _run)
_assert_not_contains "$out" "--match" "open: with no calling window, docks to the active tab"

out=$(BTOP_DOCK_EDGE=right BTOP_DOCK_SIZE=40% _run)
_assert_contains "$out" "--dock-edge=right --dock-size=40%" "open: BTOP_DOCK_EDGE and BTOP_DOCK_SIZE override the defaults"

out=$(KITTY_WINDOW_ID=8 _run)
_assert_not_contains "$out" "@ launch" "open: a btop window already in this tab is not duplicated"
_assert_contains "$out" "31" "open: ... and its id is printed"

out=$(KITTY_WINDOW_ID=8 _run --close)
_assert_contains "$out" "kitten @ close-window --match=id:31" "close: closes this tab's btop window"

out=$(_run --close)
_assert_not_contains "$out" "close-window" "close: a btop in another tab is left alone"
_assert_contains "$out" "rc=0" "close: ... and nothing to close is not an error"

# the dock runs btop with a copy of the user's config showing only the cpu box, which fits
# in a short strip (btop's own minimum with all four boxes is 24 rows)
_assert_contains "$(<$_conf)" 'shown_boxes = "cpu"' "config: only the cpu box is shown"
_assert_not_contains "$(<$_conf)" "mem" "config: ... and the others are not"
_assert_contains "$(<$_conf)" 'color_theme = "catppuccin"' "config: the rest of the user's config (theme) is kept"
_assert_contains "$(cat $_zt/home/.config/btop/btop.conf)" "cpu mem net proc" "config: the user's own config is not touched"
out=$(BTOP_DOCK_BOXES="cpu net" _run); _assert_contains "$(<$_conf)" 'shown_boxes = "cpu net"' "config: BTOP_DOCK_BOXES chooses the boxes"
rm -f $_conf; mv "$_zt/home/.config/btop/btop.conf" "$_zt/home/.config/btop/gone"
out=$(_run); _assert_contains "$(<$_conf)" 'shown_boxes = "cpu"' "config: works with no btop.conf of the user's"

rm -rf "$_zt"
if (( _failures == 0 )); then print "\nAll tests passed."; else print "\n$_failures test(s) failed."; exit 1; fi
