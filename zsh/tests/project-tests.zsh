#!/usr/bin/env zsh
_script_dir="${0:A:h}"
source "$_script_dir/../functions/project.zsh"

_pass() { echo "PASS: $1" }
_fail() { echo "FAIL: $1"; (( _failures++ )) }
_assert_eq()           { [[ "$1" == "$2" ]] && _pass "$3" || _fail "$3: expected $(printf '%q' "$2"), got $(printf '%q' "$1")" }
_assert_contains()     { [[ "$1" == *"$2"* ]] && _pass "$3" || _fail "$3: $(printf '%q' "$1") does not contain $(printf '%q' "$2")" }
_assert_not_contains() { [[ "$1" != *"$2"* ]] && _pass "$3" || _fail "$3: output unexpectedly contains $(printf '%q' "$2")" }

_tmpdir=""
_cache_file=""

setup() {
  _tmpdir=$(mktemp -d)

  mkdir -p "$_tmpdir/root1/owner/repo1/.git"
  mkdir -p "$_tmpdir/root1/owner/repo2/.git"
  mkdir -p "$_tmpdir/root2/other/proj/.git"

  _cache_file="$_tmpdir/cache.txt"
  printf '%s\n' \
    "$_tmpdir/root1/owner/repo1" \
    "$_tmpdir/root1/owner/repo2" \
    "$_tmpdir/root2/other/proj" > "$_cache_file"

  export PROJECT_ROOTS="$_tmpdir/root1:$_tmpdir/root2"
}

teardown() {
  rm -rf "$_tmpdir"
  unset PROJECT_ROOTS
}

test_parse_roots_multiple() {
  local roots; roots=$(_project_parse_roots)
  _assert_contains "$roots" "$_tmpdir/root1" "parse_roots: first root present"
  _assert_contains "$roots" "$_tmpdir/root2" "parse_roots: second root present"
}

test_parse_roots_tilde_expansion() {
  local old_roots="$PROJECT_ROOTS"
  export PROJECT_ROOTS="~/somerepo:~/other"
  local roots; roots=$(_project_parse_roots)
  _assert_contains "$roots" "$HOME/somerepo" "parse_roots: ~/somerepo expands first"
  _assert_contains "$roots" "$HOME/other" "parse_roots: ~/other expands second"
  export PROJECT_ROOTS="$old_roots"
}

test_parse_roots_tilde_only() {
  local old_roots="$PROJECT_ROOTS"
  export PROJECT_ROOTS="~"
  local roots; roots=$(_project_parse_roots)
  _assert_eq "$roots" "$HOME" "parse_roots: bare ~ expands to HOME"
  export PROJECT_ROOTS="$old_roots"
}

test_project_error_on_unset() {
  local old_roots="${PROJECT_ROOTS:-}"
  unset PROJECT_ROOTS
  local out rc
  out=$(project 2>&1); rc=$?
  [[ $rc -eq 1 ]] && _pass "project: exits 1 when PROJECT_ROOTS unset" || _fail "project: expected exit 1, got $rc"
  _assert_contains "$out" "PROJECT_ROOTS" "project: error message mentions PROJECT_ROOTS"
  export PROJECT_ROOTS="$old_roots"
}

test_project_error_on_empty() {
  local old_roots="${PROJECT_ROOTS:-}"
  export PROJECT_ROOTS=""
  local out rc
  out=$(project 2>&1); rc=$?
  [[ $rc -eq 1 ]] && _pass "project: exits 1 when PROJECT_ROOTS empty" || _fail "project: expected exit 1, got $rc"
  export PROJECT_ROOTS="$old_roots"
}

test_cache_used_when_present() {
  local list; list=$(_project_build_list "$_cache_file")
  _assert_contains "$list" "$_tmpdir/root1/owner/repo1" "cache_used: repo1 path in list"
  _assert_contains "$list" "$_tmpdir/root1/owner/repo2" "cache_used: repo2 path in list"
  _assert_contains "$list" "$_tmpdir/root2/other/proj" "cache_used: proj path in list"
}

test_cache_labels_relative() {
  local list; list=$(_project_build_list "$_cache_file")
  _assert_contains "$list" "owner/repo1" "cache_labels: repo1 label relative to root"
  _assert_contains "$list" "owner/repo2" "cache_labels: repo2 label relative to root"
  _assert_contains "$list" "other/proj" "cache_labels: proj label relative to root"
}

test_cold_start_scan_creates_cache() {
  local new_cache="$_tmpdir/new-cache.txt"
  [[ -f "$new_cache" ]] && rm -f "$new_cache"

  _project_scan "$new_cache"

  [[ -f "$new_cache" ]] && _pass "cold_start: cache file created" || _fail "cold_start: cache file not created"
  local content; content=$(cat "$new_cache")
  _assert_contains "$content" "repo1" "cold_start: repo1 found by scan"
  _assert_contains "$content" "repo2" "cold_start: repo2 found by scan"
  _assert_contains "$content" "proj"  "cold_start: proj found by scan"
}

test_cold_start_scan_absolute_paths() {
  local new_cache="$_tmpdir/abs-cache.txt"
  _project_scan "$new_cache"
  local first_line; first_line=$(head -1 "$new_cache")
  [[ "$first_line" == /* ]] && _pass "cold_start: cache contains absolute paths" || _fail "cold_start: expected absolute path, got $first_line"
}

test_open_projects_appear_first() {
  local kitty_cwds="$_tmpdir/root1/owner/repo1"
  local list; list=$(_project_build_list "$_cache_file" "$kitty_cwds")

  _assert_contains "$list" "── Open ──" "open_first: Open header present"
  _assert_contains "$list" "── All ──"  "open_first: All header present"

  local open_pos all_pos
  open_pos=$(echo "$list" | grep -n "── Open ──" | head -1 | cut -d: -f1)
  all_pos=$(echo  "$list" | grep -n "── All ──"  | head -1 | cut -d: -f1)
  [[ "$open_pos" -lt "$all_pos" ]] && _pass "open_first: Open header precedes All header" || _fail "open_first: Open not before All (open=$open_pos all=$all_pos)"

  local open_section="${list%%$'\t── All ──'*}"
  _assert_contains     "$open_section" "repo1" "open_first: open project is in Open section"
  _assert_not_contains "$open_section" "repo2" "open_first: non-open project not in Open section"

  local all_section="${list#*$'\t── All ──'}"
  _assert_not_contains "$all_section" "repo1" "open_first: open project absent from All section"
  _assert_contains     "$all_section" "repo2" "open_first: non-open project in All section"
}

test_open_cwd_subdir_matches() {
  local kitty_cwds="$_tmpdir/root1/owner/repo1/src/components"
  local list; list=$(_project_build_list "$_cache_file" "$kitty_cwds")
  local open_section="${list%%$'\t── All ──'*}"
  _assert_contains "$open_section" "repo1" "cwd_subdir: project matched by cwd in subdirectory"
}

test_no_open_group_when_empty_cwds() {
  local list; list=$(_project_build_list "$_cache_file" "")
  _assert_not_contains "$list" "── Open ──" "no_open: Open header absent when kitty_cwds empty"
  _assert_contains     "$list" "── All ──"  "no_open: All header always present"
}

# ── switch-project helpers ───────────────────────────────────────────────────

_mock_kitty_ls() {
  # Build a small kitty @ ls JSON fragment for tests.
  # Args: window_id tab_id cwd window_title tab_title
  local wid="$1" tid="$2" cwd="$3" wtitle="$4" ttitle="$5"
  printf '[{"id":1,"tabs":[{"id":%s,"title":"%s","windows":[{"id":%s,"title":"%s","foreground_processes":[{"cwd":"%s","pid":1}]}]}]}]' \
    "$tid" "$ttitle" "$wid" "$wtitle" "$cwd"
}

test_find_window_cwd_exact_match() {
  local json; json=$(_mock_kitty_ls 100 10 "/projects/my-project" "vim" "my-project")
  local result; result=$(_switch_project_find_window "/projects/my-project" "$json")
  _assert_eq "$result" "window:100" "find_window: exact cwd match returns window id"
}

test_find_window_cwd_subdir_match() {
  local json; json=$(_mock_kitty_ls 100 10 "/projects/my-project/src/components" "vim" "tab")
  local result; result=$(_switch_project_find_window "/projects/my-project" "$json")
  _assert_eq "$result" "window:100" "find_window: cwd subdir match returns window id"
}

test_find_window_title_match_fallback() {
  local json; json=$(_mock_kitty_ls 100 10 "/some/other/place" "my-project — bash" "tab")
  local result; result=$(_switch_project_find_window "/projects/my-project" "$json")
  _assert_eq "$result" "window:100" "find_window: falls back to window title when cwd misses"
}

test_find_window_tab_title_match_fallback() {
  local json; json=$(_mock_kitty_ls 100 10 "/some/other/place" "vim" "my-project")
  local result; result=$(_switch_project_find_window "/projects/my-project" "$json")
  _assert_eq "$result" "tab:10" "find_window: falls back to tab title when cwd and window title miss"
}

test_find_window_no_match() {
  local json; json=$(_mock_kitty_ls 100 10 "/some/other/place" "vim" "other-tab")
  local result; result=$(_switch_project_find_window "/projects/my-project" "$json")
  _assert_eq "$result" "" "find_window: returns empty when nothing matches"
}

test_find_window_cwd_match_wins_over_title() {
  # Window with matching cwd AND a different window with matching title — cwd wins.
  local json
  json='[{"id":1,"tabs":[
    {"id":10,"title":"other","windows":[{"id":99,"title":"my-project — vim","foreground_processes":[{"cwd":"/other","pid":2}]}]},
    {"id":11,"title":"tab","windows":[{"id":100,"title":"editor","foreground_processes":[{"cwd":"/projects/my-project","pid":1}]}]}
  ]}]'
  local result; result=$(_switch_project_find_window "/projects/my-project" "$json")
  _assert_eq "$result" "window:100" "find_window: cwd match takes priority over title match"
}

# ── switch-project cd fallback ───────────────────────────────────────────────

test_switch_project_cd_when_kitty_unavailable() {
  local proj_dir="$_tmpdir/cdtest"
  mkdir -p "$proj_dir"

  project() { echo "$proj_dir"; }
  kitty() { return 1; }

  local orig_dir="$PWD"
  switch-project "cdtest"
  local landed="$PWD"
  cd "$orig_dir"

  _assert_eq "$landed" "$proj_dir" "switch_project_cd: cds when kitty unavailable"

  unfunction project kitty
  rm -rf "$proj_dir"
}

test_switch_project_cd_when_no_matching_window() {
  local proj_dir="$_tmpdir/cdtest2"
  mkdir -p "$proj_dir"

  local no_match_json; no_match_json=$(_mock_kitty_ls 100 10 "/some/other/place" "vim" "other")
  project() { echo "$proj_dir"; }
  kitty() { echo "$no_match_json"; }

  local orig_dir="$PWD"
  switch-project "cdtest2"
  local landed="$PWD"
  cd "$orig_dir"

  _assert_eq "$landed" "$proj_dir" "switch_project_cd: cds when no matching window"

  unfunction project kitty
  rm -rf "$proj_dir"
}

test_switch_project_no_ide_on_cd_fallback() {
  local proj_dir="$_tmpdir/cdtest3"
  mkdir -p "$proj_dir"

  project() { echo "$proj_dir"; }
  kitty() { return 1; }
  local _ide_called=0
  code()   { _ide_called=1; }
  cursor() { _ide_called=1; }

  local orig_dir="$PWD"
  switch-project "cdtest3"
  cd "$orig_dir"

  (( _ide_called == 0 )) && _pass "switch_project_cd: no IDE opened on cd fallback" || _fail "switch_project_cd: IDE was unexpectedly invoked"

  unfunction project kitty code cursor
  rm -rf "$proj_dir"
}

# ── _detect_ide_command ──────────────────────────────────────────────────────

test_detect_ide_typespec() {
  local d; d=$(mktemp -d)
  touch "$d/tspconfig.yaml" "$d/package.json"
  local result; result=$(_detect_ide_command "$d")
  _assert_eq "$result" "code" "detect_ide: tspconfig.yaml → code (TypeSpec wins over package.json)"
  rm -rf "$d"
}

test_detect_ide_typescript() {
  local d; d=$(mktemp -d)
  touch "$d/package.json"
  local result; result=$(_detect_ide_command "$d")
  _assert_eq "$result" "code" "detect_ide: package.json alone → code"
  rm -rf "$d"
}

test_detect_ide_pom() {
  local d; d=$(mktemp -d)
  touch "$d/pom.xml"
  local result; result=$(_detect_ide_command "$d")
  _assert_eq "$result" "idea" "detect_ide: pom.xml → idea"
  rm -rf "$d"
}

test_detect_ide_gradle() {
  local d; d=$(mktemp -d)
  touch "$d/build.gradle"
  local result; result=$(_detect_ide_command "$d")
  _assert_eq "$result" "idea" "detect_ide: build.gradle → idea"
  rm -rf "$d"
}

test_detect_ide_gradle_kts() {
  local d; d=$(mktemp -d)
  touch "$d/build.gradle.kts"
  local result; result=$(_detect_ide_command "$d")
  _assert_eq "$result" "idea" "detect_ide: build.gradle.kts → idea"
  rm -rf "$d"
}

test_detect_ide_idea_dir() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/.idea"
  local result; result=$(_detect_ide_command "$d")
  _assert_eq "$result" "idea" "detect_ide: .idea/ dir → idea"
  rm -rf "$d"
}

test_detect_ide_unknown() {
  local d; d=$(mktemp -d)
  local result; result=$(_detect_ide_command "$d")
  _assert_eq "$result" "" "detect_ide: no known files → empty (silent skip)"
  rm -rf "$d"
}

test_switch_project_opens_ide_on_window_focus() {
  local proj_dir="$_tmpdir/idetest"
  mkdir -p "$proj_dir"
  touch "$proj_dir/package.json"

  local match_json; match_json=$(_mock_kitty_ls 200 20 "$proj_dir" "bash" "idetest")
  project() { echo "$proj_dir"; }
  kitty() {
    if [[ "$1" == "@" && "$2" == "ls" ]]; then echo "$match_json"; return 0; fi
    return 0
  }
  local _ide_called=0
  code() { _ide_called=1; }

  switch-project "idetest"

  (( _ide_called == 1 )) && _pass "switch_project_ide: code called when focusing existing window" || _fail "switch_project_ide: code was not called"

  unfunction project kitty code
  rm -rf "$proj_dir"
}

test_switch_project_no_ide_on_cd() {
  local proj_dir="$_tmpdir/ideskip"
  mkdir -p "$proj_dir"
  touch "$proj_dir/package.json"

  project() { echo "$proj_dir"; }
  kitty() { return 1; }
  local _ide_called=0
  code() { _ide_called=1; }

  local orig_dir="$PWD"
  switch-project "ideskip"
  cd "$orig_dir"

  (( _ide_called == 0 )) && _pass "switch_project_ide: no IDE on cd fallback" || _fail "switch_project_ide: IDE unexpectedly called on cd"

  unfunction project kitty code
  rm -rf "$proj_dir"
}

# ── --refresh / PROJECT_CACHE ────────────────────────────────────────────────

test_project_cache_env_var() {
  local old_cache="${PROJECT_CACHE:-}"
  export PROJECT_CACHE="$_tmpdir/custom-cache.txt"
  local cf; cf=$(_project_cache_file)
  _assert_eq "$cf" "$_tmpdir/custom-cache.txt" "project_cache_env_var: PROJECT_CACHE respected"
  [[ -n "$old_cache" ]] && export PROJECT_CACHE="$old_cache" || unset PROJECT_CACHE
}

test_project_cache_env_var_tilde() {
  local old_cache="${PROJECT_CACHE:-}"
  export PROJECT_CACHE="~/my-cache"
  local cf; cf=$(_project_cache_file)
  _assert_eq "$cf" "$HOME/my-cache" "project_cache_env_var_tilde: ~ expanded in PROJECT_CACHE"
  [[ -n "$old_cache" ]] && export PROJECT_CACHE="$old_cache" || unset PROJECT_CACHE
}

test_refresh_finds_depth1_repos() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/root/direct-repo/.git"
  local cache="$d/cache.txt"
  local old_roots="$PROJECT_ROOTS"
  export PROJECT_ROOTS="$d/root"

  _project_scan "$cache"

  local content; content=$(cat "$cache")
  _assert_contains "$content" "direct-repo" "refresh_depth1: repo at depth 1 found"
  [[ "$(head -1 "$cache")" == /* ]] && _pass "refresh_depth1: absolute path" || _fail "refresh_depth1: not absolute path"

  export PROJECT_ROOTS="$old_roots"
  rm -rf "$d"
}

test_refresh_finds_depth2_repos() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/root/org/nested-repo/.git"
  local cache="$d/cache.txt"
  local old_roots="$PROJECT_ROOTS"
  export PROJECT_ROOTS="$d/root"

  _project_scan "$cache"

  local content; content=$(cat "$cache")
  _assert_contains "$content" "nested-repo" "refresh_depth2: repo at depth 2 found"

  export PROJECT_ROOTS="$old_roots"
  rm -rf "$d"
}

test_refresh_skips_missing_root_with_warning() {
  local missing="/nonexistent/path/project-test-$$"
  local d; d=$(mktemp -d)
  mkdir -p "$d/real/repo/.git"
  local old_roots="$PROJECT_ROOTS"
  export PROJECT_ROOTS="$missing:$d/real"

  local cache="$_tmpdir/miss-cache.txt"
  local err_out
  err_out=$( { _project_scan "$cache"; } 2>&1 )

  _assert_contains "$err_out" "$missing" "refresh_missing_root: warning mentions missing root"
  local content; content=$(cat "$cache" 2>/dev/null || echo "")
  _assert_contains "$content" "repo" "refresh_missing_root: valid repos still found"

  export PROJECT_ROOTS="$old_roots"
  rm -rf "$d"
}

test_refresh_writes_cache_with_correct_content() {
  local d; d=$(mktemp -d)
  mkdir -p "$d/src/org/alpha/.git"
  mkdir -p "$d/src/org/beta/.git"
  local old_roots="$PROJECT_ROOTS"
  export PROJECT_ROOTS="$d/src"
  local cache="$_tmpdir/rw-cache.txt"

  _project_scan "$cache"

  [[ -f "$cache" ]] && _pass "refresh_writes_cache: cache file created" || _fail "refresh_writes_cache: cache file not created"
  local content; content=$(cat "$cache")
  _assert_contains "$content" "alpha" "refresh_writes_cache: alpha in cache"
  _assert_contains "$content" "beta"  "refresh_writes_cache: beta in cache"

  export PROJECT_ROOTS="$old_roots"
  rm -rf "$d"
}

test_project_refresh_flag_rebuilds_cache() {
  # Re-source: earlier tests unfunctioned `project` via `unfunction project kitty`
  source "$_script_dir/../functions/project.zsh"

  local old_cache="${PROJECT_CACHE:-}"
  local cache="$_tmpdir/rebuild-cache.txt"
  export PROJECT_CACHE="$cache"

  # Override picker to avoid interactive fzf
  _project_picker() { echo ""; }

  project --refresh

  [[ -f "$cache" ]] && _pass "project_refresh: cache written after --refresh" || _fail "project_refresh: cache not written"
  local content; content=$(cat "$cache" 2>/dev/null || echo "")
  _assert_contains "$content" "repo1" "project_refresh: repos present in rebuilt cache"

  unfunction _project_picker
  [[ -n "$old_cache" ]] && export PROJECT_CACHE="$old_cache" || unset PROJECT_CACHE
}

# ── run ─────────────────────────────────────────────────────────────────────

_failures=0
setup

test_parse_roots_multiple
test_parse_roots_tilde_expansion
test_parse_roots_tilde_only
test_project_error_on_unset
test_project_error_on_empty
test_cache_used_when_present
test_cache_labels_relative
test_cold_start_scan_creates_cache
test_cold_start_scan_absolute_paths
test_open_projects_appear_first
test_open_cwd_subdir_matches
test_no_open_group_when_empty_cwds
test_find_window_cwd_exact_match
test_find_window_cwd_subdir_match
test_find_window_title_match_fallback
test_find_window_tab_title_match_fallback
test_find_window_no_match
test_find_window_cwd_match_wins_over_title
test_switch_project_cd_when_kitty_unavailable
test_switch_project_cd_when_no_matching_window
test_switch_project_no_ide_on_cd_fallback
test_detect_ide_typespec
test_detect_ide_typescript
test_detect_ide_pom
test_detect_ide_gradle
test_detect_ide_gradle_kts
test_detect_ide_idea_dir
test_detect_ide_unknown
test_switch_project_opens_ide_on_window_focus
test_switch_project_no_ide_on_cd
test_project_cache_env_var
test_project_cache_env_var_tilde
test_refresh_finds_depth1_repos
test_refresh_finds_depth2_repos
test_refresh_skips_missing_root_with_warning
test_refresh_writes_cache_with_correct_content
test_project_refresh_flag_rebuilds_cache

teardown

echo ""
if (( _failures == 0 )); then
  echo "All tests passed."
else
  echo "$_failures test(s) failed."
  exit 1
fi
