# Claude Code session lookups for a kitty window whose foreground process is a
# running `claude`: its conversation title and its agent state. Sourced by
# zsh/bin/window-list, zsh/bin/next-agent and zsh/bin/sw-preview.
#
# Everything here reads ~/.claude*/sessions/<pid>.json — undocumented internal
# state that could change between Claude Code versions — so a missing or
# malformed file means "nothing to report", never an error.
#
# ~/.claude*/sessions/<pid>.json is also never cleaned up when the `claude`
# process exits, so a pid can later be reused by an unrelated process — matching
# on pid alone would then attach a stale title or state to whatever now happens
# to be running in that window. Callers guard against this with kitty's own live
# `foreground_processes[-1].cmdline[0]`: only look a pid up here when that
# process actually is `claude` right now. (A pid reused by a *new* claude process
# needs no such guard: that process overwrites its own session file with fresh
# data as soon as it starts.)

# Prints the path of the session file for a claude process's pid, if any.
_claude_session_file() {
  local pid=$1
  [[ -z "$pid" ]] && return
  # A `claude` process may be running under a non-default config dir (e.g.
  # CLAUDE_CONFIG_DIR=~/.claude-k for a separate work profile) — its
  # sessions/projects live entirely under that dir instead of ~/.claude, so
  # every ~/.claude* directory that looks like a config dir has to be checked.
  # Should two of them have a file for this pid (one left by a dead process
  # whose pid has been reused), the most recently modified is the live one's.
  local -a session_files
  session_files=(~/.claude*/sessions/$pid.json(N.om))
  (( $#session_files )) && print -r -- $session_files[1]
}

# Claude session titles.
#
# sessions/<pid>.json's "name" field is NOT the conversation title shown in
# Claude Code's own UI/history — it's a short slug (e.g. "project-tools-8f")
# derived at startup, used as an addressable session name elsewhere. The actual
# human-facing title (e.g. "Window switcher fzf colors") is generated later and
# recorded as a `{"type":"ai-title","aiTitle":"..."}` line appended to that
# session's own transcript, at
# <config-dir>/projects/<project-slug>/<sessionId>.jsonl (sessionId comes from
# the pid's session file). The project-slug directory name is a lossy transform
# of the project's cwd — not just "/" but also e.g. "." becomes "-" — so rather
# than reproduce that transform (and risk drifting from it), find the
# transcript by its sessionId, which is unique regardless of slug. Take the
# *last* ai-title line (the title can be regenerated as the conversation
# evolves). Falls back to the session file's "name" slug if no ai-title has
# been recorded yet (e.g. a very new session) or the transcript can't be found.
#
# An interactive session can also delegate to a background job (a separate
# claude process, with its own pid and sessions/<pid>.json, "kind":"bg") and
# "park" on it — the interactive session's own file then carries a
# "parkedJobId" matching the job's own "jobId". While parked, the interactive
# session's own transcript typically has no ai-title yet (nothing's been said
# in it since the job started), so its window would otherwise show the
# interactive session's bare derived slug (e.g. "context-e1") even though the
# job's own "name" (e.g. "sources/ publishing design") is the descriptive title
# actually visible in that terminal. So: prefer this session's own ai-title;
# failing that, follow parkedJobId to the job's session file (scanning sibling
# session files in the same config dir for a matching "jobId") and use its
# title by the same rule (its own ai-title, else its "name"); failing that,
# fall back to this session's own "name" slug.
_claude_session_title() {
  local session_file
  session_file=$(_claude_session_file "$1")
  [[ -z "$session_file" ]] && return
  _claude_session_title_from_file "${session_file:h:h}" "$session_file"
}

# Given a config dir and one of its sessions/<pid>.json files, prints the best
# available title for it — see the "parked on a background job" note above.
_claude_session_title_from_file() {
  local config_dir=$1 session_file=$2
  local session_id name parked_job_id
  session_id=$(jq -r '.sessionId // empty' "$session_file" 2>/dev/null)
  name=$(jq -r '.name // empty' "$session_file" 2>/dev/null)
  parked_job_id=$(jq -r '.parkedJobId // empty' "$session_file" 2>/dev/null)
  if [[ -n "$session_id" ]]; then
    local transcript
    transcript=$(find "$config_dir/projects" -mindepth 2 -maxdepth 2 -name "$session_id.jsonl" -print -quit 2>/dev/null)
    if [[ -n "$transcript" ]]; then
      local title
      title=$(jq -r 'select(.type == "ai-title") | .aiTitle' "$transcript" 2>/dev/null | tail -1)
      [[ -n "$title" ]] && { print -r -- "$title"; return }
    fi
  fi
  if [[ -n "$parked_job_id" ]]; then
    local f job_file
    for f in "$config_dir"/sessions/*.json(N); do
      [[ "$f" == "$session_file" ]] && continue
      [[ "$(jq -r '.jobId // empty' "$f" 2>/dev/null)" == "$parked_job_id" ]] && { job_file=$f; break }
    done
    if [[ -n "$job_file" ]]; then
      local job_title
      job_title=$(_claude_session_title_from_file "$config_dir" "$job_file")
      [[ -n "$job_title" ]] && { print -r -- "$job_title"; return }
    fi
  fi
  [[ -n "$name" ]] && print -r -- "$name"
}

# Agent state. (kitty/focus_watcher.py and python/tidy-windows-advise/advise
# apply the same rules in Python — keep the three in step.)
#
# The session file carries "status" (busy | shell | idle | waiting) and
# "statusUpdatedAt" (ms epoch, written only when the status changes — an idle
# session's stays put for hours). Prints `STATE<TAB>SINCE`, SINCE being that
# change in epoch seconds, where STATE is:
#
#   blocked  waiting on you (a permission prompt or a question)
#   working  busy
#   done     idle, and it went idle after you last looked at its window
#   idle     idle, and you've seen it
#
# "shell" counts as idle: it isn't documented, but a session sits in it after
# its turn has finished (seemingly while a shell command it started is still
# running in the background), so it is waiting for you just as an idle one is.
#
# "Last looked" is the window's `seen_at` user var, stamped by
# kitty/focus_watcher.py on focus gain and loss (pass it as $2; anything
# non-numeric means the watcher never saw this window, which is then never
# `done`). The window you're in right now ($3 = 1) is never `done` either: you
# are looking at it. Prints nothing for an unrecognised status.
_claude_session_state() {
  local pid=$1 seen_at=$2 is_current=$3
  local session_file row session_status since state
  session_file=$(_claude_session_file "$pid")
  [[ -z "$session_file" ]] && return
  row=$(jq -r '[.status // "-", ((.statusUpdatedAt // 0) / 1000 | floor)] | join(" ")' "$session_file" 2>/dev/null) || return
  read -r session_status since <<< "$row"
  [[ "$since" == <-> ]] || return
  case $session_status in
    waiting) state=blocked ;;
    busy)    state=working ;;
    idle|shell)
      state=idle
      [[ "$seen_at" == <-> && "$is_current" != 1 ]] && (( since > seen_at )) && state='done'
      ;;
    *) return ;;
  esac
  print -r -- "$state"$'\t'"$since"
}

# The one-character state column the pickers start a window's row with: a
# coloured marker for a `claude` window's agent state, a blank for every other
# window so labels stay aligned.
_claude_session_marker() {
  case $1 in
    blocked) print -rn -- $'\033[1;31m!\033[0m' ;;
    working) print -rn -- $'\033[33m…\033[0m' ;;
    'done')  print -rn -- $'\033[1;32m✓\033[0m' ;;
    idle)    print -rn -- $'\033[2m·\033[0m' ;;
    *)       print -rn -- ' ' ;;
  esac
}
