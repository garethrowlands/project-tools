#!/usr/bin/env zsh
# Tests for the Claude agent-state side of the window switcher, and for
# saving the windows as a session: the real zsh/bin/window-list,
# zsh/bin/next-agent and zsh/bin/save-session, run against a fake kitty (canned
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
elif [[ "$1 $2 $3 $4" == "@ action save_as_session --save-only" ]]; then
  cp '$T'/saved.session $5
fi
return 0' >| $T/bin/kitty
chmod +x $T/bin/kitty
print -r -- '#!/bin/zsh
[[ -s '$T'/ps.out ]] && cat '$T'/ps.out
return 0' >| $T/bin/ps
chmod +x $T/bin/ps

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

# --- window-list: a window that has rung the bell ---

jq '(.[0].tabs[0].windows[] | select(.id == 2 or .id == 6)) |= . + {needs_attention: true}' $T/ls.json >| $T/tmp.json && mv $T/tmp.json $T/ls.json
LIST=$(list 7)
is 'a window with an unseen bell ends in one'    "$(row 6)" '  zsh f 🔔'
is 'the bell follows an agent row too'           "$(row 2)" '… slug-102 b 🔔'
is 'no bell on a window that has not rung'       "$(row 1)" '! slug-101 a'
windows 7 $ALL

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

# save-session: kitty's own session file, with each claude window resuming its
# session. Window 3 is a shell, 5 the overlay save-session runs in, and 6 a
# claude under another config dir.
save_session() { HOME=$T/home PATH=$T/bin:$PATH KITTY_WINDOW_ID=${2:-5} zsh -f $ROOT/zsh/bin/save-session $1 }
windows 2 2:claude:b:1000 3:zsh:c:1000 6:claude:f:1000
rm $T/home/.claude/sessions/106.json
session 106 idle 2000 .claude-k
SAVED="new_tab proj
layout tall
cd /p/b
launch 'kitty-unserialize-data={\"id\": 2}' --var=seen_at=1000 --var=agent_state=done --title=keep
launch 'kitty-unserialize-data={\"id\": 5}' --type=overlay save-session
focus
launch 'kitty-unserialize-data={\"id\": 3}' --cwd=/p/c
launch 'kitty-unserialize-data={\"id\": 6}' --cwd=/p/f"
print -r -- "$SAVED" >| $T/saved.session
is 'save-session: reports what it saved'         "$(save_session $T/s/out.session)" "saved 3 windows, 2 Claude sessions, 0 other commands to $T/s/out.session"
is 'save-session: claude windows resume'         "$(<$T/s/out.session)" "new_tab proj
layout tall
cd /p/b
launch 'kitty-unserialize-data={\"id\":2,\"cmd_at_shell_startup\":\"setopt aliases; eval \\\"claude --resume sid-102 <\$TTY >\$TTY 2>&1\\\"\"}' --title=keep
focus
launch 'kitty-unserialize-data={\"id\": 3}' --cwd=/p/c
launch 'kitty-unserialize-data={\"id\":6,\"cmd_at_shell_startup\":\"setopt aliases; eval \\\"claudek --resume sid-106 <\$TTY >\$TTY 2>&1\\\"\"}' --cwd=/p/f"
is 'save-session: default file'                  "$(save_session)" "saved 3 windows, 2 Claude sessions, 0 other commands to $T/home/.config/kitty/sessions/restore.kitty-session"
save_session $T/s/shell.session 3 >/dev/null
is 'save-session: run from a shell, it is kept'  "$(grep -c '"id": 3' $T/s/shell.session)" 1
: >| $T/saved.session
is 'save-session: nothing saved, old file kept'  "$(save_session $T/s/out.session 2>&1; grep -c resume $T/s/out.session)" "kitty saved no session
2"

# a claude suspended with Ctrl+Z: the window's foreground is its shell (pid
# 500), and claude (pid 104) a stopped child of it
print -r -- "$SAVED" >| $T/saved.session
jq '.[0].tabs[0].windows |= map(if .id == 3 then .pid = 500 else . end)' $T/ls.json >| $T/tmp.json && mv $T/tmp.json $T/ls.json
print -r -- '  500   104 /usr/local/bin/claude --resume x
  500   777 vim claude
    1   105 claude' >| $T/ps.out
save_session $T/s/out.session >/dev/null
is 'save-session: a suspended claude resumes'    "$(grep '"id":3' $T/s/out.session)" "launch 'kitty-unserialize-data={\"id\":3,\"cmd_at_shell_startup\":\"setopt aliases; eval \\\"claude --resume sid-104 <\$TTY >\$TTY 2>&1\\\"\"}' --cwd=/p/c"
: >| $T/ps.out

# a window in the middle of a command comes back with it typed, not run: 3 was
# running a dev server; 2 is a claude, which resumes instead; 6 is at its
# prompt; 9 (not in the session) is where save-session was typed
startup() { print -r -- ${${"$(grep "\"id\":$1" $T/s/out.session)"#*data=}%%\' --*} | jq -r .cmd_at_shell_startup }
print -r -- "$SAVED" >| $T/saved.session
jq --arg cmd "FOO=1 pnpm dev | tee 'my log'" '.[0].tabs[0].windows |= map(
      if .id == 3 then .pid = 3 | .at_prompt = false | .last_reported_cmdline = $cmd
      elif .id == 2 then .at_prompt = false | .last_reported_cmdline = "claude"
      else .at_prompt = true | .last_reported_cmdline = "ls" end)' $T/ls.json >| $T/tmp.json && mv $T/tmp.json $T/ls.json
is 'save-session: counts the other commands'      "$(save_session $T/s/out.session 9)" "saved 4 windows, 2 Claude sessions, 1 other commands to $T/s/out.session"
is 'save-session: a running command comes back typed' "$(startup 3)" "print -z -- 'FOO=1 pnpm dev | tee '\''my log'\'''"
typed=$(grep '"id":3' $T/s/out.session)
is 'save-session: its quotes do not end the word' "${#${typed//[^\']/}}" 2
is 'save-session: a claude still resumes'         "$(startup 2)" 'setopt aliases; eval "claude --resume sid-102 <$TTY >$TTY 2>&1"'
is 'save-session: a window at its prompt is left' "$(grep -c '"id": 6\|"id":6,"cmd_at_shell_startup":"print' $T/s/out.session)" 0
save_session $T/s/self.session 3 >/dev/null
is 'save-session: not the window it was run from' "$(grep -c 'print -z' $T/s/self.session)" 0

# a pager is run, not typed; a pager fed by another command is only typed
pager() {
  jq --arg cmd "$1" '.[0].tabs[0].windows |= map(if .id == 3 then .last_reported_cmdline = $cmd else . end)' $T/ls.json >| $T/tmp.json && mv $T/tmp.json $T/ls.json
  save_session $T/s/out.session 9 >/dev/null
  startup 3
}
is 'save-session: a pager is run'                 "$(pager "less 'my file'")" "setopt aliases; eval 'less '\''my file'\''' '<\$TTY >\$TTY 2>&1'"
is 'save-session: man is a pager'                 "$(pager 'man zsh')" "setopt aliases; eval 'man zsh' '<\$TTY >\$TTY 2>&1'"
is 'save-session: a command piped to one is typed' "$(pager 'make deploy | less')" "print -z -- 'make deploy | less'"
is 'save-session: lesspipe is not less'           "$(pager 'lessc site.less')" "print -z -- 'lessc site.less'"

exit $fail
