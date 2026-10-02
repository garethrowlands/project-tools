#!/usr/bin/env zsh
source "${0:A:h}/sw.zsh"

_pass() { print "PASS: $1" }
_fail() { print "FAIL: $1"; (( _failures++ )) }
_assert_eq() { [[ "$1" == "$2" ]] && _pass "$3" || _fail "$3: expected $(printf '%q' "$2"), got $(printf '%q' "$1")" }

integer _failures=0

# ── fixtures ──────────────────────────────────────────────────────────────────
# repo on main, plus old-branch (no worktree), fix-foo (worktree under
# .claude/worktrees, most recent commit) and a detached worktree beside the repo.

_zt=$(mktemp -d "${TMPDIR:-/tmp}/sw-test-XXXXXX")
_zt=${_zt:A}
_g() { git -c user.name=t -c user.email=t@t "$@" }
git init -q -b main "$_zt/repo"
cd "$_zt/repo"
GIT_COMMITTER_DATE=2020-01-01T00:00:00Z _g commit -q --allow-empty -m a
_g branch old-branch
GIT_COMMITTER_DATE=2020-01-02T00:00:00Z _g commit -q --allow-empty -m b
_g worktree add -q .claude/worktrees/fix-foo -b fix-foo
GIT_COMMITTER_DATE=2020-01-03T00:00:00Z _g -C .claude/worktrees/fix-foo commit -q --allow-empty -m c
_g worktree add -q --detach ../elsewhere

_display() { _sw_list | cut -f3 | sed $'s/\e\\[[0-9]*m//g' }

# ── _sw_list ──────────────────────────────────────────────────────────────────

out=$(_display)
_assert_eq "$out" "  ⎇ fix-foo     .claude/worktrees/fix-foo
* ⎇ main        (main worktree)
  ⎇ (detached)  ../elsewhere
    old-branch  " \
  "_sw_list: worktrees first by recency, short paths, current marked"

out=$(cd .claude/worktrees/fix-foo && _display | grep '^\*')
_assert_eq "$out" "* ⎇ fix-foo     .claude/worktrees/fix-foo" "_sw_list: marks current worktree from inside a linked one"

out=$(_sw_list | awk -F'\t' '$2 == "fix-foo" { print $1 }')
_assert_eq "$out" "$_zt/repo/.claude/worktrees/fix-foo" "_sw_list: first field is the full worktree path"

out=$(_sw_list | awk -F'\t' '$2 == "old-branch" { print "[" $1 "]" }')
_assert_eq "$out" "[]" "_sw_list: branch without a worktree has empty path"

out=$(cd "$_zt" && _sw_list 2>&1)
_assert_eq "$out" "sw: not in a git repository" "_sw_list: errors outside a repo"

# ── _sw_worktree_path ────────────────────────────────────────────────────────

_assert_eq "$(_sw_worktree_path /a/context feat/unit-inventory-file)" "/a/context-unit-inventory-file" \
  "_sw_worktree_path: drops leading prefix segment"
_assert_eq "$(_sw_worktree_path /a/context feat/x/y)" "/a/context-x-y" \
  "_sw_worktree_path: remaining slashes become dashes"
_assert_eq "$(_sw_worktree_path /a/context old-branch)" "/a/context-old-branch" \
  "_sw_worktree_path: branch without prefix used as is"

# ── sw (fzf stubbed: prints key $_key, then the first match for $_q) ──────────

fzf() { print -r -- "$_key"; command fzf --filter "$_q" | head -1 }
_g branch feat/new-thing
_g branch other

out=$(_q=fix-foo; sw; pwd)
_assert_eq "$out" "$_zt/repo/.claude/worktrees/fix-foo" "sw: picking a worktree cds there"

out=$(_q=old-branch; sw 2>/dev/null; git branch --show-current)
_assert_eq "$out" "old-branch" "sw: picking a plain branch git-switches to it"

out=$(_q=feat/new-thing _key=ctrl-o; sw >/dev/null 2>&1; pwd; git branch --show-current)
_assert_eq "$out" "$_zt/repo-new-thing"$'\n'"feat/new-thing" "sw: ctrl-o on a plain branch creates a sibling worktree and cds there"

out=$(_q=fix-foo _key=ctrl-o; sw; pwd)
_assert_eq "$out" "$_zt/repo/.claude/worktrees/fix-foo" "sw: ctrl-o on a worktree just cds there"

mkdir "$_zt/repo-other"
_before=$(git worktree list)
out=$(_q=other _key=ctrl-o; sw 2>&1; print "rc=$?")
_assert_eq "$out" "sw: $_zt/repo-other already exists"$'\n'"rc=1" "sw: ctrl-o errors if the target folder exists"
_assert_eq "$(git worktree list)" "$_before" "sw: ctrl-o collision leaves worktrees unchanged"

cd / && rm -rf "$_zt"

# ── summary ───────────────────────────────────────────────────────────────────

if (( _failures == 0 )); then
  print "\nAll tests passed."
else
  print "\n$_failures test(s) failed."
  exit 1
fi
