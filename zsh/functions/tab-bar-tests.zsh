#!/usr/bin/env zsh
# Tests for bin/tab-bar against a fake `kitten` that records its arguments.

_pass() { print "PASS: $1" }
_fail() { print "FAIL: $1"; (( _failures++ )) }
_assert_eq() { [[ "$1" == "$2" ]] && _pass "$3" || _fail "$3: expected $(printf '%q' "$2"), got $(printf '%q' "$1")" }

integer _failures=0
_tb=${0:A:h}/../bin/tab-bar
_zt=$(mktemp -d "${TMPDIR:-/tmp}/tab-bar-test-XXXXXX"); _zt=${_zt:A}
mkdir -p "$_zt/bin" "$_zt/home"
print -r -- '#!/bin/zsh
print -r -- "kitten ${(j: :)@}" >> '$_zt'/calls
[[ -n "$FAKE_FAIL" ]] && exit 1
exit 0' > "$_zt/bin/kitten"
chmod +x "$_zt/bin/kitten"

# runs tab-bar and prints the calls made; zsh -f keeps the user's ~/.zshenv from
# putting the real kitten first on PATH, and no listen socket reaches a live kitty
_run() {
  : > "$_zt/calls"
  HOME="$_zt/home" XDG_CACHE_HOME= KITTY_LISTEN_ON= KITTY_PID=${PID:-100} PATH="$_zt/bin:$PATH" zsh -f "$_tb" "$@" >/dev/null 2>&1
  print "rc=$?"; cat "$_zt/calls"
}
H='kitten @ load-config -o tab_bar_edge=bottom -o tab_bar_style=powerline -o tab_title_max_lines=1 -o tab_title_max_length=0'
V='kitten @ load-config --ignore-overrides
kitten @ load-config'
N='kitten @ load-config -o tab_bar_style=hidden'

_assert_eq "$(_run horizontal)" "rc=0
$H" "horizontal: overrides the tab bar's edge, style and lines"
_assert_eq "$(_run vertical)" "rc=0
$V" "vertical: drops the overrides, then reloads again (the bar needs it after none)"
_assert_eq "$(_run none)" "rc=0
$N" "none: hides the tab bar"
_run vertical >/dev/null
_assert_eq "$(_run)" "rc=0
$H" "toggle from the configured (vertical) bar goes horizontal"
_assert_eq "$(_run toggle)" "rc=0
$N" "toggle from horizontal goes to none"
_assert_eq "$(_run toggle)" "rc=0
$V" "toggle from none goes back to vertical"
_assert_eq "$(_run toggle)" "rc=0
$H" "and round again"
_assert_eq "$(PID=200 _run toggle)" "rc=0
$H" "a new kitty (another pid) is vertical, so toggle goes horizontal"
_assert_eq "$(TAB_BAR_EDGE=top _run horizontal | sed -n 2p)" "kitten @ load-config -o tab_bar_edge=top -o tab_bar_style=powerline -o tab_title_max_lines=1 -o tab_title_max_length=0" "TAB_BAR_EDGE picks the edge"
_run vertical >/dev/null
_assert_eq "$(FAKE_FAIL=1 _run horizontal | head -1)" "rc=1" "a failing kitten is an error"
_assert_eq "$(_run toggle | sed -n 2p)" "$H" "...and does not count as the mode: the next toggle is horizontal"
_run vertical >/dev/null; _run none >/dev/null
_assert_eq "$(_run toggle | sed -n 2,3p)" "$V" "toggle remembers none across calls"
_assert_eq "$(_run bogus | head -1)" "rc=2" "an unknown mode is a usage error"

rm -rf "$_zt"
if (( _failures == 0 )); then print "\nAll tests passed."; else print "\n$_failures test(s) failed."; exit 1; fi
