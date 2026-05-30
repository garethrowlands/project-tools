#!/usr/bin/env zsh
source "${0:A:h}/notes-lib.zsh"

_pass() { echo "PASS: $1" }
_fail() { echo "FAIL: $1"; (( _failures++ )) }
_assert_eq()       { [[ "$1" == "$2" ]] && _pass "$3" || _fail "$3: expected $(printf '%q' "$2"), got $(printf '%q' "$1")" }
_assert_contains() { [[ "$1" == *"$2"* ]] && _pass "$3" || _fail "$3: $(printf '%q' "$1") does not contain $(printf '%q' "$2")" }
_assert_not_contains() { [[ "$1" != *"$2"* ]] && _pass "$3" || _fail "$3: output unexpectedly contains $(printf '%q' "$2")" }

setup() {
  _vault=$(mktemp -d)

  cat > "$_vault/simple.md" <<'EOF'
---
title: Simple Note
---
Body content here.
EOF

  cat > "$_vault/multiline.md" <<'EOF'
---
title: >-
  Multiline Title Here
---
Content.
EOF

  cat > "$_vault/with-excerpt.md" <<'EOF'
---
title: Note With Excerpt
---
> ## Excerpt
> -> This is the excerpt text
EOF

  cat > "$_vault/untitled.md" <<'EOF'
---
tags:
- foo
---
Just some content.
EOF

  cat > "$_vault/quoted.md" <<'EOF'
---
title: "Quoted Title Without Surrounding Quotes"
---
Content.
EOF

  cat > "$_vault/flow-wrap.md" <<'EOF'
---
title: "First Line of Title
  And Second Line"
---
Content.
EOF

  cat > "$_vault/quoted-source.md" <<'EOF'
---
title: Quoted Source
source: "https://example.com/path"
---
Content.
EOF
}

teardown() {
  rm -rf "$_vault"
}

test_title_list_basic() {
  local out; out=$(_notes_title_list "$_vault")
  _assert_contains "$out" "simple.md::Simple Note" "title_list: simple inline title"
}

test_title_list_multiline() {
  local out; out=$(_notes_title_list "$_vault")
  _assert_contains "$out" "multiline.md::Multiline Title Here" "title_list: multiline title joined"
}

test_title_list_with_excerpt() {
  local out; out=$(_notes_title_list "$_vault")
  _assert_contains "$out" "with-excerpt.md::Note With Excerpt" "title_list: title present when excerpt exists"
  _assert_contains "$out" "This is the excerpt text" "title_list: excerpt text appended"
}

test_title_list_quoted_string() {
  local out; out=$(_notes_title_list "$_vault")
  _assert_contains "$out" 'quoted.md::Quoted Title Without Surrounding Quotes' "title_list: YAML double-quotes stripped"
  _assert_not_contains "$out" '"Quoted Title' "title_list: no surrounding quotes in output"
}

test_title_list_flow_wrap() {
  local out; out=$(_notes_title_list "$_vault")
  _assert_contains "$out" 'flow-wrap.md::First Line of Title And Second Line' "title_list: wrapped flow scalar joined"
}

test_title_list_excludes_untitled() {
  local out; out=$(_notes_title_list "$_vault")
  _assert_not_contains "$out" "untitled.md" "title_list: untitled file excluded"
}

test_all_list_includes_titled() {
  local out; out=$(_notes_all_list "$_vault")
  _assert_contains "$out" "simple.md::Simple Note" "all_list: titled file present"
}

test_all_list_includes_untitled_with_basename() {
  local out; out=$(_notes_all_list "$_vault")
  _assert_contains "$out" "untitled.md::untitled" "all_list: untitled file uses basename"
}

test_all_list_includes_excerpt() {
  local out; out=$(_notes_all_list "$_vault")
  _assert_contains "$out" "This is the excerpt text" "all_list: excerpt included"
}

test_title_map_file_format() {
  local map; map=$(_notes_title_map_file "$_vault")
  local content; content=$(cat "$map")
  rm -f "$map"
  _assert_contains "$content" "simple.md	Simple Note" "title_map: filepath TAB title"
  _assert_not_contains "$content" "untitled.md" "title_map: untitled file absent"
}

test_url_extraction_strips_quotes() {
  local url; url=$(rg -m1 -A1 "^(source|url): " "$_vault/quoted-source.md" | grep -oE "https?://[^[:space:]\"]+" | head -1)
  _assert_eq "$url" "https://example.com/path" "url extraction: quoted source has no trailing quote"
}

test_sentinel_parsing_body() {
  local result="§body§my search query"
  local query="${result#§body§}"
  _assert_eq "$query" "my search query" "sentinel: §body§ prefix stripped"
}

test_sentinel_parsing_title() {
  local result="§title§another query"
  local query="${result#§title§}"
  _assert_eq "$query" "another query" "sentinel: §title§ prefix stripped"
}

test_sentinel_parsing_empty_query() {
  local result="§body§"
  local query="${result#§body§}"
  _assert_eq "$query" "" "sentinel: empty query after prefix"
}

test_sentinel_no_extra_quotes() {
  # fzf shell-escapes {q} so a simple word arrives unquoted; verify stripping works cleanly
  local result="§body§confluent"
  local query="${result#§body§}"
  _assert_eq "$query" "confluent" "sentinel: no surrounding quotes on simple word"
}

# ── integration tests against the real vault ─────────────────────────────────

test_real_title_list_nonempty() {
  local count; count=$(_notes_title_list | wc -l | tr -d ' ')
  [[ $count -gt 0 ]] && _pass "real title_list: non-empty ($count entries)" || _fail "real title_list: empty"
}

test_real_title_list_known_note() {
  local out; out=$(_notes_title_list)
  _assert_contains "$out" "Payments.md::Payments" "real title_list: Payments.md has title Payments"
}

test_real_all_list_count_matches_files() {
  local file_count; file_count=$(rg --files --glob '*.md' "$HOME/notes" | wc -l | tr -d ' ')
  local list_count; list_count=$(_notes_all_list | wc -l | tr -d ' ')
  _assert_eq "$list_count" "$file_count" "real all_list: count matches rg --files ($file_count files)"
}

test_real_title_map_nonempty() {
  local map; map=$(_notes_title_map_file)
  local count; count=$(wc -l < "$map" | tr -d ' ')
  rm -f "$map"
  [[ $count -gt 0 ]] && _pass "real title_map: non-empty ($count entries)" || _fail "real title_map: empty"
}

test_real_quoted_titles_stripped() {
  local out; out=$(_notes_title_list)
  _assert_contains "$out" '30093 - Order Amendment Service - HLD - Kingfisher Architecture Team' "real: quoted title has quotes stripped"
  _assert_not_contains "$out" '"30093' "real: no leading quote in output"
}

test_real_flow_wrap_title_joined() {
  local out; out=$(_notes_title_list)
  _assert_contains "$out" 'NEW FIELD' "real: flow-wrap title contains [NEW FIELD]"
  _assert_contains "$out" 'Order Sourcing sub-domain' "real: flow-wrap title second line joined"
}

test_real_excerpt_in_title_list() {
  local out; out=$(_notes_title_list)
  _assert_contains "$out" "Kitty CheatSheet" "real title_list: Kitty CheatSheet with excerpt"
}

# ── run ──────────────────────────────────────────────────────────────────────

_failures=0
setup

test_title_list_basic
test_title_list_multiline
test_title_list_with_excerpt
test_title_list_quoted_string
test_title_list_flow_wrap
test_title_list_excludes_untitled
test_all_list_includes_titled
test_all_list_includes_untitled_with_basename
test_all_list_includes_excerpt
test_title_map_file_format
test_url_extraction_strips_quotes
test_sentinel_parsing_body
test_sentinel_parsing_title
test_sentinel_parsing_empty_query
test_sentinel_no_extra_quotes

teardown

echo ""
echo "── integration (real vault) ─────────────────────────────────────────────"
test_real_title_list_nonempty
test_real_title_list_known_note
test_real_all_list_count_matches_files
test_real_title_map_nonempty
test_real_excerpt_in_title_list
test_real_quoted_titles_stripped
test_real_flow_wrap_title_joined

echo ""
if (( _failures == 0 )); then
  echo "All tests passed."
else
  echo "$_failures test(s) failed."
  exit 1
fi
