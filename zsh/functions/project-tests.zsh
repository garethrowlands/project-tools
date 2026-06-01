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

_ls_file=$(mktemp /tmp/project-test-XXXXXX)
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

# ── summary ───────────────────────────────────────────────────────────────────

if (( _failures == 0 )); then
  print "\nAll tests passed."
else
  print "\n$_failures test(s) failed."
  exit 1
fi
