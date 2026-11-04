#!/usr/bin/env zsh
# Tests for bin/ide: opening a project, and a file at a line, with fake `code`
# and `open` on PATH that record their arguments.

_pass() { print "PASS: $1" }
_fail() { print "FAIL: $1"; (( _failures++ )) }
_assert_eq() { [[ "$1" == "$2" ]] && _pass "$3" || _fail "$3: expected $(printf '%q' "$2"), got $(printf '%q' "$1")" }

integer _failures=0
_ide=${0:A:h}/../bin/ide

_zt=$(mktemp -d "${TMPDIR:-/tmp}/ide-test-XXXXXX")
_zt=${_zt:A}

# ── fixtures ──────────────────────────────────────────────────────────────────
# repo: IntelliJ project (go.mod); web: VS Code project (.vscode)

_g() { git -c user.name=t -c user.email=t@t "$@" }
git init -q -b main "$_zt/repo"
mkdir -p "$_zt/repo/src" "$_zt/repo/odd dir"
: > "$_zt/repo/go.mod"
: > "$_zt/repo/src/Main.go"
: > "$_zt/repo/my file.go"
: > "$_zt/repo/odd:5.txt"
git init -q -b main "$_zt/web"
mkdir -p "$_zt/web/.vscode"
: > "$_zt/web/app.ts"
ln -s "$_zt/repo" "$_zt/link"

mkdir -p "$_zt/bin" "$_zt/home"
for _cmd in code open; do
  print -r -- '#!/bin/zsh
print -r -- "'$_cmd' ${(j: :)${(q)@}}" >> '$_zt'/calls' > "$_zt/bin/$_cmd"
  chmod +x "$_zt/bin/$_cmd"
done

# runs ide with the given arguments from $_zt; prints what the fakes were
# called with, then "rc=N" and anything ide said
_ide() {
  : > "$_zt/calls"
  local out rc
  out=$(cd "$_zt" && HOME=$_zt/home PATH=$_zt/bin:$PATH IDE_JUMP_DELAY=0 zsh -f "$_ide" "$@" 2>&1)
  rc=$?
  cat "$_zt/calls"
  [[ -n $out ]] && print -r -- "said: $out"
  print "rc=$rc"
}

_open_project="open -a IntelliJ\\ IDEA $_zt/repo"

# ── without a line: as before ────────────────────────────────────────────────

_assert_eq "$(_ide repo/src/Main.go)" "$_open_project
rc=0" "a file without a line opens just its project in IntelliJ"
_assert_eq "$(_ide repo)" "$_open_project
rc=0" "a directory opens its project in IntelliJ"
_assert_eq "$(_ide web/app.ts)" "code --reuse-window $_zt/web
rc=0" "a file without a line opens just its project in VS Code"

# ── IntelliJ: open the project, then the file at the line ────────────────────

_assert_eq "$(_ide repo/src/Main.go:42)" "$_open_project
open idea://open\\?file=${${_zt}//\//%2F}%2Frepo%2Fsrc%2FMain.go\\&line=42
rc=0" "IntelliJ: path:line opens the project, then jumps with the idea:// URL"
_assert_eq "$(_ide repo/src/Main.go:42:7)" "$_open_project
open idea://open\\?file=${${_zt}//\//%2F}%2Frepo%2Fsrc%2FMain.go\\&line=42\\&column=7
rc=0" "IntelliJ: path:line:column adds the column"
_assert_eq "$(_ide 'repo/my file.go:3')" "$_open_project
open idea://open\\?file=${${_zt}//\//%2F}%2Frepo%2Fmy%20file.go\\&line=3
rc=0" "IntelliJ: spaces in the path are percent-encoded"
_assert_eq "$(_ide link/src/Main.go:5)" "$_open_project
open idea://open\\?file=${${_zt}//\//%2F}%2Frepo%2Fsrc%2FMain.go\\&line=5
rc=0" "IntelliJ: a path through a symlink is resolved first"

# ── VS Code ──────────────────────────────────────────────────────────────────

_assert_eq "$(_ide web/app.ts:9)" "code --reuse-window --goto $_zt/web/app.ts:9 $_zt/web
rc=0" "VS Code: path:line goes to the project with --goto"
_assert_eq "$(_ide web/app.ts:9:3)" "code --reuse-window --goto $_zt/web/app.ts:9:3 $_zt/web
rc=0" "VS Code: path:line:column keeps the column"

# ── awkward arguments ────────────────────────────────────────────────────────

_assert_eq "$(_ide repo/odd:5.txt)" "$_open_project
rc=0" "a path that exists with a colon in its name is a path, not path:line"
_assert_eq "$(_ide repo/src:4)" "said: ide: repo/src is a directory, so it can't take a line number
rc=1" "a line number on a directory is an error"
_assert_eq "$(_ide repo/src/Nope.go:4)" "said: ide: no such file: repo/src/Nope.go
rc=1" "a line number on a file that doesn't exist is an error"

cd / && rm -rf "$_zt"

# ── summary ───────────────────────────────────────────────────────────────────

if (( _failures == 0 )); then
  print "\nAll tests passed."
else
  print "\n$_failures test(s) failed."
  exit 1
fi
