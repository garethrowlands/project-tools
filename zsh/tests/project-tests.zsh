#!/usr/bin/env zsh
source "${0:A:h}/../functions/project.zsh"

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

teardown

echo ""
if (( _failures == 0 )); then
  echo "All tests passed."
else
  echo "$_failures test(s) failed."
  exit 1
fi
