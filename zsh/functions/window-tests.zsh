#!/usr/bin/env zsh
# Tests for the Claude agent-state side of the window switcher: the real
# zsh/bin/window-list and zsh/bin/next-agent, run against a fake kitty (canned
# `@ ls`, records every call) on PATH, and a temp $HOME holding Claude session
# files. Needs neither kitty nor Claude Code.
#
#   zsh zsh/functions/window-tests.zsh
#
# Exits 1 if any test fails.

ROOT=${0:A:h:h:h}
T=$(mktemp -d)
trap 'rm -rf $T' EXIT
fail=0

ok()  { print -r "PASS $1" }
bad() { print -r "FAIL $1"; fail=1 }
is()  { [[ $2 == "$3" ]] && ok $1 || bad "$1: got ${(q+)2}, want ${(q+)3}" }

mkdir -p $T/bin $T/home/.claude/sessions $T/home/.claude-k/sessions $T/home/.claude-k/projects/-p-i
print -r -- '#!/bin/zsh
print -r -- "$*" >> '$T'/kitty.calls
if [[ "$*" == "@ ls --match state:overlay_parent" ]]; then
  [[ -s '$T'/parent.json ]] && cat '$T'/parent.json
elif [[ $1 == @ && $2 == ls ]]; then
  cat '$T'/ls.json
fi
return 0' >| $T/bin/kitty
chmod +x $T/bin/kitty

# session PID STATUS SINCE_SECONDS [CONFIG_DIR] [EXTRA_JSON]
session() {
  jq -n --argjson pid $1 --arg s $2 --argjson since $3 --argjson extra ${5:-'{}'} \
    '{pid: $pid, sessionId: "sid-\($pid)", name: "slug-\($pid)", status: $s, statusUpdatedAt: ($since * 1000)} + $extra' \
    >| $T/home/${4:-.claude}/sessions/$1.json
}

# windows ACTIVE_ID SPEC... — writes `kitty @ ls` for one focused OS window with
# one tab "proj"; each SPEC is ID:PROC:CWD_BASENAME:SEEN_AT (pid is 100 + ID,
# an empty SEEN_AT means no user var). ACTIVE_ID is the window next-agent's
# overlay covers; the overlay itself (id 99, is_self) is the tab's active window.
windows() {
  local active=$1; shift
  print -rl -- "$@" | jq -R --argjson active $active '
    split(":") | (.[0] | tonumber) as $id |
    {id: $id, title: "t", is_self: false, is_focused: false, is_active: false,
     user_vars: (if .[3] == "" then {} else {seen_at: .[3]} end),
     foreground_processes: [{pid: (100 + $id), cwd: "/p/\(.[2])", cmdline: ["/usr/local/bin/\(.[1])"]}]}
  ' | jq -s '. + [{id: 99, title: "next-agent", is_self: true, is_focused: true, is_active: true, user_vars: {},
                   foreground_processes: [{pid: 199, cwd: "/p", cmdline: ["zsh"]}]}] |
             [{is_focused: true, tabs: [{id: 1, title: "proj", is_focused: true, is_active: true, windows: .}]}]' >| $T/ls.json
  jq --argjson active $active '.[0].tabs[0].windows |= map(select(.id == $active))' $T/ls.json >| $T/parent.json
}

# zsh -f: the user's ~/.zshenv would put the real kitty back first on PATH
list() {
  : >| $T/order
  HOME=$T/home PATH=$T/bin:$PATH WINDOW_CURRENT_ID=$1 zsh -f $ROOT/zsh/bin/window-list $T/closed $T/order \
    | sed $'s/\033\\[[0-9;]*m//g'
}
# a row's label, the padding between its name and project squeezed to one space
row() { print -r -- "$LIST" | awk -F'\t' -v id=$1 '$1 == id {print $2}' | sed 's/\([^ ]\)  */\1 /g' }
# relist — like list, but keeps the order file, as fzf's reload after a close does
relist() {
  HOME=$T/home PATH=$T/bin:$PATH zsh -f $ROOT/zsh/bin/window-list $T/closed $T/order \
    | sed $'s/\033\\[[0-9;]*m//g'
}
ids() { print -r -- "$LIST" | cut -f1 | tr '\n' ' ' }
next_agent() {
  : >| $T/kitty.calls
  HOME=$T/home PATH=$T/bin:$PATH zsh -f $ROOT/zsh/bin/next-agent "$@" >| $T/out
  grep '^@ focus-window' $T/kitty.calls
}

session 101 waiting 500
session 102 busy 2000
session 103 idle 2000
session 104 idle 2000
session 105 idle 2000
session 106 waiting 2000
session 107 idle 2000
session 109 waiting 400 .claude-k
print -r -- '{"type":"ai-title","aiTitle":"Old title"}
{"type":"user"}
{"type":"ai-title","aiTitle":"Real title"}' >| $T/home/.claude-k/projects/-p-i/sid-109.jsonl
session 110 idle 2000 .claude '{"parkedJobId": "job-1"}'
session 999 busy 2000 .claude '{"jobId": "job-1", "kind": "bg", "name": "the parked job"}'
jq 'del(.name)' $T/home/.claude/sessions/110.json >| $T/tmp.json && mv $T/tmp.json $T/home/.claude/sessions/110.json

ALL=(1:claude:a:1000 2:claude:b:1000 3:claude:c:1000 4:claude:d:3000 5:claude:e: 6:zsh:f:1000
     7:claude:g:1000 8:claude:h:1000 9:claude:i:1000 10:claude:j:3000)

# --- window-list: one marker per state ---

: >| $T/closed
windows 7 $ALL
LIST=$(list 7)
is 'waiting is blocked'                          "$(row 1)" '! slug-101 a'
is 'busy is working'                             "$(row 2)" '… slug-102 b'
is 'idle since after seen_at is done'            "$(row 3)" '✓ slug-103 c'
is 'idle since before seen_at is idle'           "$(row 4)" '· slug-104 d'
is 'idle with no seen_at is never done'          "$(row 5)" '· slug-105 e'
is 'a stale session file for a non-claude pid'   "$(row 6)" '  zsh f'
is 'the current window is never done'            "$(row 7)" '· slug-107 g'
is 'claude with no session file has no marker'   "$(row 8)" '  claude h'
is 'other config dir: state and last ai-title'   "$(row 9)" '! Real title i'
is 'parked session takes the job'"'"'s title'    "$(row 10)" '· the parked job j'
is 'rows stay in kitty order, then their tab'    "$(ids)" '1 2 3 4 5 6 7 8 9 10 tab:1 '
is 'the tab is a header row'                     "$(row tab:1)" '── proj'
is 'projects line up after the longest name'     "$(print -r -- "$LIST" | awk -F'\t' '$1 == 6 {print $2}')" '  zsh             f'

# --- window-list: one header per tab, after its windows (fzf lists bottom-up,
# so that shows it above them) ---

# two_tabs TITLE ID... — moves those windows to a second tab (id 2) called TITLE
two_tabs() {
  local title=$1; shift
  jq --arg title $title --argjson ids "[${(j:,:)@}]" '
    .[0].tabs[0].windows as $w |
    .[0].tabs[0].windows = [$w[] | select(.id as $i | $ids | index($i) | not)] |
    .[0].tabs += [{id: 2, title: $title, is_focused: false, is_active: false,
                   windows: [$w[] | select(.id as $i | $ids | index($i))]}]
  ' $T/ls.json >| $T/tmp.json && mv $T/tmp.json $T/ls.json
}
windows 1 1:claude:proj:1000 6:zsh:f:1000 2:claude:b:1000 3:zsh:other:1000
two_tabs '~/src/some/other' 2 3
LIST=$(list 1)
is 'each tab follows its own windows'            "$(ids)" '1 6 tab:1 2 3 tab:2 '
is 'a path for a tab title is cut to its tail'   "$(row tab:2)" '── other'
is 'a window names its project'                  "$(row 2)" '… slug-102 b'
is 'even when it is the tab'"'"'s own'           "$(row 3)" '  zsh other'

# closing: the row stays put, dimmed, under its header; a header closes nothing
print -r -- "$LIST" | cut -f1 | sed 's/^closed://' >| $T/order
: >| $T/kitty.calls
HOME=$T/home PATH=$T/bin:$PATH zsh -f $ROOT/zsh/bin/window-list $T/closed $T/order close tab:2
is 'closing a header row does nothing'           "$(grep -c close-window $T/kitty.calls)" '0'
HOME=$T/home PATH=$T/bin:$PATH zsh -f $ROOT/zsh/bin/window-list $T/closed $T/order close 2
HOME=$T/home PATH=$T/bin:$PATH zsh -f $ROOT/zsh/bin/window-list $T/closed $T/order close 3
is 'closing a window asks kitty to'              "$(grep -c close-window $T/kitty.calls)" '2'
jq 'del(.[0].tabs[1])' $T/ls.json >| $T/tmp.json && mv $T/tmp.json $T/ls.json
LIST=$(relist)
is 'a closed tab keeps its header and rows'      "$(ids)" '1 6 tab:1 closed:2 closed:3 tab:2 '
is 'a closed row keeps its label'                "$(row closed:2)" '[closed] slug-102 b'
: >| $T/closed

# "shell" is idle by another name
session 113 shell 2000
windows 1 13:claude:m:1000 14:claude:m:3000
session 114 shell 2000
LIST=$(list 1)
is 'shell since after seen_at is done'           "$(row 13)" '✓ slug-113 m'
is 'shell since before seen_at is idle'          "$(row 14)" '· slug-114 m'
windows 2 2:claude:b:1000 13:claude:m:1000 4:claude:d:3000
is 'next-agent seeks out a finished shell one'   "$(next_agent)" '@ focus-window --match id:13'

# pid 101 again, left behind in the other config dir by a dead process
session 101 busy 100 .claude-k
touch -t 202001010000 $T/home/.claude-k/sessions/101.json
windows 7 1:claude:a:1000
LIST=$(list 7)
is 'two config dirs, one pid: the newer file'    "$(row 1)" '! slug-101 a'
rm $T/home/.claude-k/sessions/101.json

print -r -- '{"pid": 111, "status": "thinking", "statusUpdatedAt": 1}' >| $T/home/.claude/sessions/111.json
print -r -- 'not json' >| $T/home/.claude/sessions/112.json
windows 1 11:claude:k:1000 12:claude:l:1000
LIST=$(list 1)
is 'an unknown status has no marker'             "$(row 11)" '  claude k'
is 'a malformed session file has no marker'      "$(row 12)" '  claude l'

# --- next-agent: agents needing you first (blocked before done, longest-standing
# first, cycling); with none, the next agent window in kitty order ---

windows 7 $ALL
is 'from elsewhere: the longest-blocked agent'   "$(next_agent)" '@ focus-window --match id:9'
windows 9 $ALL
is 'from that one: the next blocked agent'       "$(next_agent)" '@ focus-window --match id:1'
windows 1 $ALL
is 'from the last blocked one: the done agent'   "$(next_agent)" '@ focus-window --match id:3'
windows 3 $ALL
is 'from the done one (now seen): wraps round'   "$(next_agent)" '@ focus-window --match id:9'

# (window 7 is done too whenever it isn't the current window)
windows 9 $ALL
is '--prev from the first: wraps to the last'    "$(next_agent --prev)" '@ focus-window --match id:7'
windows 1 $ALL
is '--prev from the second: back to the first'   "$(next_agent --prev)" '@ focus-window --match id:9'
windows 7 $ALL
is '--prev from elsewhere: the last needing you' "$(next_agent --prev)" '@ focus-window --match id:3'

QUIET=(2:claude:b:1000 4:claude:d:3000 6:zsh:f:1000 8:claude:h:1000)
windows 4 $QUIET
is 'none needs you: the next agent window'       "$(next_agent)" '@ focus-window --match id:8'
is 'none needs you: nothing printed'             "$(<$T/out)" ''
windows 8 $QUIET
is 'none needs you: wraps round'                 "$(next_agent)" '@ focus-window --match id:2'
windows 2 $QUIET
is 'none needs you, --prev: wraps to the last'   "$(next_agent --prev)" '@ focus-window --match id:8'
windows 6 $QUIET
is 'from a non-agent window: the first agent'    "$(next_agent)" '@ focus-window --match id:2'
is 'from a non-agent window, --prev: the last'   "$(next_agent --prev)" '@ focus-window --match id:8'

windows 1 1:claude:a:1000 2:claude:b:1000
is 'only the current one needs you: next agent'  "$(next_agent)" '@ focus-window --match id:2'

windows 2 2:claude:b:1000 6:zsh:f:1000
is 'the only agent window: stays put'            "$(next_agent)" ''

# run from a shell there is no overlay: the current window is the active one
windows 9 $ALL
jq '.[0].tabs[0].windows |= map(select(.id != 99) | .is_active = (.id == 9))' $T/ls.json >| $T/tmp.json && mv $T/tmp.json $T/ls.json
: >| $T/parent.json
is 'no overlay: current is the active window'    "$(next_agent)" '@ focus-window --match id:1'

exit $fail
