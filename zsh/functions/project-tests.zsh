#!/usr/bin/env zsh
source "${0:A:h}/project.zsh"

_pass() { print "PASS: $1" }
_fail() { print "FAIL: $1"; (( _failures++ )) }
_assert_eq()       { [[ "$1" == "$2" ]] && _pass "$3" || _fail "$3: expected $(printf '%q' "$2"), got $(printf '%q' "$1")" }
_assert_contains() { [[ "$1" == *"$2"* ]] && _pass "$3" || _fail "$3: $(printf '%q' "$1") does not contain $(printf '%q' "$2")" }
_assert_empty()        { [[ -z "$1" ]] && _pass "$2" || _fail "$2: expected empty, got $(printf '%q' "$1")" }
_assert_not_contains() { [[ "$1" != *"$2"* ]] && _pass "$3" || _fail "$3: output unexpectedly contains $(printf '%q' "$2")" }

integer _failures=0

# ── fixtures ──────────────────────────────────────────────────────────────────

_ls_file=$(mktemp "${TMPDIR:-/tmp}/project-test-XXXXXX")
cat > "$_ls_file" <<'EOF'
[{
  "active_tab_history": [],
  "tabs": [{
    "windows": [
      {
        "id": 1,
        "title": "zsh",
        "foreground_processes": [{
          "cmdline": ["-zsh"],
          "cwd": "/home/user/myproject",
          "pid": 100
        }]
      },
      {
        "id": 2,
        "title": "editor",
        "foreground_processes": [{
          "cmdline": ["nvim", "src/main.rs"],
          "cwd": "/home/user/myproject/src",
          "pid": 101
        }]
      },
      {
        "id": 3,
        "title": "null-cwd",
        "foreground_processes": [{
          "cmdline": ["kitten"],
          "cwd": null,
          "pid": 102
        }]
      },
      {
        "id": 4,
        "title": "other",
        "foreground_processes": [{
          "cmdline": ["-zsh"],
          "cwd": "/home/user/otherproject",
          "pid": 102
        }]
      }
    ]
  }]
}]
EOF

# ── _project_preview_windows ──────────────────────────────────────────────────

out=$(_project_preview_windows /home/user/myproject "$_ls_file")
_assert_contains "$out" "Windows" "_project_preview_windows: header shown"
_assert_contains "$out" "zsh" "_project_preview_windows: shell process shown"
_assert_contains "$out" "nvim" "_project_preview_windows: editor process shown"
_assert_contains "$out" "src" "_project_preview_windows: subdir path shown"

out=$(_project_preview_windows /home/user/otherproject "$_ls_file")
_assert_contains "$out" "Windows" "_project_preview_windows: exact match only shows correct project"
_assert_not_contains "$out" "otherproject" "_project_preview_windows: non-matching project excluded"

out=$(_project_preview_windows /home/user/myproject "$_ls_file")
_assert_contains "$out" "nvim" "_project_preview_windows: null cwd window is skipped without error"

out=$(_project_preview_windows /home/user/myproject "")
_assert_empty "$out" "_project_preview_windows: empty ls_file produces no output"

out=$(_project_preview_windows /home/user/myproject /nonexistent/file)
_assert_empty "$out" "_project_preview_windows: missing ls_file produces no output"

out=$(_project_preview_windows /home/user/nowhere "$_ls_file")
_assert_empty "$out" "_project_preview_windows: no matching windows produces no output"

rm -f "$_ls_file"

# ── zoxide fixtures ───────────────────────────────────────────────────────────
# roots/a, roots/b, roots/c: scanned repos (in the cache)
# roots/a-worktrees/feat:    linked worktree of roots/a (.git file)
# roots/sub:                 submodule of roots/b (.git file into .git/modules)
# extra/d:                   repo outside PROJECT_ROOTS
# plain:                     not a repo

_zt=$(mktemp -d "${TMPDIR:-/tmp}/project-test-XXXXXX"); _zt=${_zt:A}
mkdir -p "$_zt"/roots/{a,b,c}/.git "$_zt"/roots/a/src "$_zt"/roots/a-worktrees/feat \
  "$_zt"/roots/sub "$_zt"/extra/d/.git "$_zt"/plain
print "gitdir: $_zt/roots/a/.git/worktrees/feat" > "$_zt/roots/a-worktrees/feat/.git"
print "gitdir: ../b/.git/modules/sub"            > "$_zt/roots/sub/.git"
_zcache="$_zt/projects.txt"
printf '%s\n' "$_zt/roots/a" "$_zt/roots/b" "$_zt/roots/c" > "$_zcache"

# ── _project_zoxide_scores ────────────────────────────────────────────────────

zoxide() {
  printf '%6.1f %s\n' 20 "$_zt/plain" 10 "$_zt/extra/d" 4 "$_zt/roots/a-worktrees/feat" 7 "$_zt/roots/sub"
}
out=$(_project_zoxide_scores)
_assert_contains "$out" $'10.0\t'"$_zt/extra/d"$'\trepo' "_project_zoxide_scores: .git dir is a repo"
_assert_contains "$out" $'4.0\t'"$_zt/roots/a-worktrees/feat"$'\twt:'"$_zt/roots/a" "_project_zoxide_scores: worktree resolves to main repo"
_assert_contains "$out"$'\n' $'7.0\t'"$_zt/roots/sub"$'\t\n' "_project_zoxide_scores: submodule has no kind"
_assert_contains "$out" $'20.0\t'"$_zt/plain"$'\t' "_project_zoxide_scores: plain dir has no kind"
unfunction zoxide

out=$(path=(); _project_zoxide_scores)
_assert_empty "$out" "_project_zoxide_scores: no zoxide produces no output"

# ── _project_build_list ───────────────────────────────────────────────────────

PROJECT_ROOTS="$_zt/roots"
_zscores=$(printf '%s\t%s\t%s\n' \
  5  "$_zt/roots/b"                repo \
  3  "$_zt/roots/a/src"            "" \
  4  "$_zt/roots/a-worktrees/feat" "wt:$_zt/roots/a" \
  10 "$_zt/extra/d"                repo \
  7  "$_zt/roots/sub"              "" \
  20 "$_zt/plain"                  "")

out=$(_project_build_list "$_zcache")
_assert_eq "$out" $'\t── All ──\n'"$_zt/roots/a"$'\ta\n'"$_zt/roots/b"$'\tb\n'"$_zt/roots/c"$'\tc' \
  "_project_build_list: no scores keeps alphabetical order"

out=$(_project_build_list "$_zcache" "" "$_zscores")
_assert_eq "$out" $'\t── All ──\n'"$_zt/extra/d"$'\t'"$_zt/extra/d"$'\n'"$_zt/roots/a"$'\ta\n'"$_zt/roots/b"$'\tb\n'"$_zt/roots/c"$'\tc' \
  "_project_build_list: ranked by score, subdir + worktree roll up, non-repos dropped"

out=$(HOME="$_zt" _project_build_list "$_zcache" "" "$_zscores")
_assert_contains "$out" "$_zt/extra/d"$'\t~/extra/d' "_project_build_list: discovered repo label is ~-abbreviated"

out=$(_project_build_list "$_zcache" "$_zt/roots/a-worktrees/feat/src"$'\n'"$_zt/roots/c" "$_zscores")
_assert_eq "$out" $'\t── Open ──\n'"$_zt/roots/a"$'\t* a\n'"$_zt/roots/c"$'\t* c\n\t── All ──\n'"$_zt/extra/d"$'\t'"$_zt/extra/d"$'\n'"$_zt/roots/b"$'\tb' \
  "_project_build_list: window in worktree marks main repo open; open group ranked"

out=$(_project_build_list "$_zcache" "" $'1\t'"$_zt/extra/d/wt"$'\twt:'"$_zt/extra/d")
_assert_contains "$out" "$_zt/extra/d"$'\t' "_project_build_list: worktree's main repo is added when outside the cache"

rm -rf "$_zt"

# ── summary ───────────────────────────────────────────────────────────────────

if (( _failures == 0 )); then
  print "\nAll tests passed."
else
  print "\n$_failures test(s) failed."
  exit 1
fi
