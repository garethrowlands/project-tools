#!/usr/bin/env zsh
# Tests for bin/hunk-dock against a fake `kitten` that records its arguments and
# answers `@ ls` from $FAKE_LS.

_pass() { print "PASS: $1" }
_fail() { print "FAIL: $1"; (( _failures++ )) }
_assert_eq()       { [[ "$1" == "$2" ]] && _pass "$3" || _fail "$3: expected $(printf '%q' "$2"), got $(printf '%q' "$1")" }
_assert_contains() { [[ "$1" == *"$2"* ]] && _pass "$3" || _fail "$3: $(printf '%q' "$1") does not contain $(printf '%q' "$2")" }
_assert_not_contains() { [[ "$1" != *"$2"* ]] && _pass "$3" || _fail "$3: output unexpectedly contains $(printf '%q' "$2")" }

integer _failures=0
_hd=${0:A:h}/../bin/hunk-dock
_zt=$(mktemp -d "${TMPDIR:-/tmp}/hunk-dock-test-XXXXXX"); _zt=${_zt:A}
mkdir -p "$_zt/bin" "$_zt/repo" "$_zt/other"
print -r -- '#!/bin/zsh
print -r -- "kitten ${(j: :)${(q)@}}" >> '$_zt'/calls
if [[ "$2" == ls ]]; then print -r -- "$FAKE_LS"; fi
if [[ "$2" == launch ]]; then print 42; fi' > "$_zt/bin/kitten"
chmod +x "$_zt/bin/kitten"

# runs hunk-dock from $_zt/repo; prints the calls made, then its output and rc=N
_run() {
  : > "$_zt/calls"
  local out rc
  # zsh -f: the user's ~/.zshenv would put the real kitten first on PATH; no listen socket
  # either, so nothing can reach a live kitty
  out=$(cd "$_zt/repo" && KITTY_LISTEN_ON= PATH="$_zt/bin:$PATH" zsh -f "$_hd" "$@" 2>&1); rc=$?
  cat "$_zt/calls"; print -r -- "$out"; print "rc=$rc"
}
_ls_hunk_in() {  # $1 = cwd of an existing window titled hunk
  print -r -- '[{"tabs":[{"id":1,"title":"t","windows":[
    {"id":7,"title":"claude","cwd":"'$_zt'/repo"},
    {"id":31,"title":"hunk","cwd":"'$1'"}]}]}]'
}

export FAKE_LS='[{"tabs":[{"id":1,"title":"t","windows":[{"id":7,"title":"claude","cwd":"'$_zt'/repo"}]}]}]'
unset HUNK_DOCK_EDGE HUNK_DOCK_SIZE
export KITTY_WINDOW_ID=7

out=$(_run)
_assert_contains "$out" "kitten @ launch --type=window-dock --dock-edge=top --dock-size=65% --match=window_id:7 --keep-focus --title=hunk --cwd=$_zt/repo hunk diff --watch" \
  "open: docks Hunk at the top, 65%, in the caller's tab, without taking focus"
_assert_contains "$out" "42" "open: prints the new window's id"

out=$(_run "$_zt/other")
_assert_contains "$out" "--cwd=$_zt/other hunk diff --watch" "open: a directory argument is the repo"

out=$(_run --staged --mode split)
_assert_contains "$out" "--cwd=$_zt/repo hunk diff --watch --staged --mode split" "open: other arguments pass through to hunk"

out=$(_run "$_zt/other" main..HEAD)
_assert_contains "$out" "--cwd=$_zt/other hunk diff --watch main..HEAD" "open: DIR then hunk arguments"

out=$(_run -- main..HEAD)
_assert_contains "$out" "--cwd=$_zt/repo hunk diff --watch main..HEAD" "open: -- ends dock options"

out=$(KITTY_WINDOW_ID= _run)
_assert_not_contains "$out" "--match" "open: with no calling window, docks to the active tab"

out=$(HUNK_DOCK_EDGE=right HUNK_DOCK_SIZE=40% _run)
_assert_contains "$out" "--dock-edge=right --dock-size=40%" "open: HUNK_DOCK_EDGE and HUNK_DOCK_SIZE override the defaults"

export FAKE_LS=$(_ls_hunk_in "$_zt/repo")
out=$(_run)
_assert_not_contains "$out" "@ launch" "open: a hunk window already in the repo is not duplicated"
_assert_contains "$out" "31" "open: ... and its id is printed"

export FAKE_LS=$(_ls_hunk_in "$_zt/other")
out=$(_run)
_assert_contains "$out" "@ launch" "open: a hunk window for another repo does not count"

export FAKE_LS=$(_ls_hunk_in "$_zt/repo")
out=$(_run --close)
_assert_contains "$out" "kitten @ close-window --match=id:31" "close: closes the repo's hunk window"

export FAKE_LS='[{"tabs":[{"id":1,"title":"t","windows":[{"id":7,"title":"claude","cwd":"'$_zt'/repo"}]}]}]'
out=$(_run --close)
_assert_not_contains "$out" "close-window" "close: nothing open, nothing closed"
_assert_contains "$out" "rc=0" "close: ... and that is not an error"

rm -rf "$_zt"
if (( _failures == 0 )); then print "\nAll tests passed."; else print "\n$_failures test(s) failed."; exit 1; fi
