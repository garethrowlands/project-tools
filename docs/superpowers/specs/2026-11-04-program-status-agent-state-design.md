# Agent state from the Program Status Protocol (OSC 7501)

Status: step 1 implemented in `kitty/focus_watcher.py` (not yet deployed to the
live kitty config); step 2 is a proposal.

## Problem

`kitty/focus_watcher.py` works out each Claude Code agent's state
(blocked / working / done / idle) by polling every 2 seconds. It finds the
window's `claude` process, reads `~/.claude*/sessions/<pid>.json` (undocumented
internal state), and combines it with a `seen_at` user var to decide whether a
finished turn is "done since you looked". The same rules are copied into
`zsh/functions/claude-session.zsh` and `python/tidy-windows-advise/advise`
("keep the three in step").

kitty 0.50.0 supports the Program Status Protocol (OSC 7501), and Claude Code
(2.1.318 tested; support arrived in 2.1.295) already reports its state through
it, once the terminal answers its startup query. That replaces guessing from a
private file with a documented signal pushed by the program itself.

## What was verified (2026-11-04, kitty 0.50.0, Claude Code 2.1.318)

Observed through `kitten @ ls` (`program_status` on each window) in a real
session and in a scratch kitty running `claude`:

- Claude sends `app: claude-code`, with `state` one of `working`, `blocked`,
  `done`, `idle`. `msg`, `title`, `id`, `kind` and `progress` were empty or
  null.
- `working` appears when a turn starts; `blocked` appeared about 2 seconds
  later when a permission prompt was shown.
- `done` appears when the turn finishes and **stays while the window is not
  focused** (held for over a minute); it was gone after the window was
  focused. This is kitty's documented rule, and it is the same meaning as the
  current `✓` ("finished since you last looked").
- `idle`, `working` and `blocked` records are dropped by kitty at the next
  shell prompt (needs shell integration) or when a `launch --hold` program
  exits. `done` and `error` last until focus or a key press.
- Not explained: two `claude --resume` windows had `agent_state: idle` but an
  empty `program_status`. Possibly just the idle-record rules above; not
  confirmed.
- Not tested: how `{tab.program_status}` renders in `tab_title_template`;
  `error` from Claude. (`done` arriving in a window you are looking at is
  decided, see Notifications.)

## Design

Use the status records as the primary source of `agent_state`; keep the
session-file lookup as a fallback. The `agent_state` user var and everything
downstream (`tab_bar.py` markers, `window`/`next-agent`/`tidy-windows` via
`kitten @ ls` user vars, notifications) stay as they are.

### State mapping

From a window's records, consider those with `app == "claude-code"` and take
the most pressing state:

| records contain | `agent_state` |
|---|---|
| `blocked` | `blocked` |
| `done` | `done` |
| `working` | `working` |
| `idle` | `idle` |
| none | fall back to the session file (below) |

`error` is ignored for now (Claude was not observed to send it). Other apps'
records are ignored; a window running some other program that reports status
does not get an agent marker.

Pure function `state_from_records(records) -> str` (empty string for no
claude-code record). It takes no `msg` and no `title`: those can carry command
text or paths, and the design never reads them.

### Triggers

- Add `on_program_status_change(boss, window, data)` to `focus_watcher.py`.
  `data['program_status']` is the full list of current records. Compute the
  state with `state_from_records` and call the existing `refresh`-style
  publish: set the `agent_state` var, mark the tab bar dirty, and notify on
  a transition into `blocked` or `done` when the window is not being looked at.
  This makes the markers and notifications immediate, with no 2-second lag.
- Keep `on_focus_change` stamping `seen_at`: the fallback still uses it, and
  `tidy-windows` reads it for idle time. Its immediate `refresh` is kept so a
  `✓` clears as you arrive on the fallback path; on the status path kitty
  clears `done` itself and `on_program_status_change` fires.
- The timer poll stays. It runs the same `window_state` for every window,
  which takes the records first and reads the session file only for windows
  with none, so the two sources never fight.

### Fallback

Used when a window has a live `claude` foreground process but no
`claude-code` record: older Claude Code, a terminal that didn't answer the
handshake, windows created before the watcher loaded (global watchers only
receive callbacks for windows created after they load), or idle records
dropped at a prompt. The fallback is today's code unchanged
(`window_state`, `agent_state`, `session_file`), so the three-way "keep in
step" note shrinks to two copies (`claude-session.zsh`, `advise`) plus the
fallback, rather than growing.

### Notifications

Unchanged: only on a transition into `blocked` or `done`, only when
`is_looked_at` is false, same title/body, click focuses the window.

Decided: if `done` arrives while the window is focused, publish it anyway.
Kitty keeps the record until a key press, so the tab shows `✓` for the tab you
are on until you next type. That is fine, and simpler than special-casing it.
It differs from the fallback path, which never shows `done` for a window you
are looking at; leave that as is. No notification either way when looked at.

## Staging

Step 1 is everything above: the watcher keeps publishing `agent_state`, now
from the status records first, so `tab_bar.py` and the shell tools are
untouched. It is the smallest change and the lowest risk.

Step 2, once step 1 has proven itself in daily use, slims things down:

- `window.program_status` is readable from anywhere in kitty, so `tab_bar.py`
  can derive its markers from it directly in `draw_title`, with no
  `agent_state` var in between. (Check that kitty redraws the tab bar when
  the status changes; if it doesn't, `on_program_status_change` calls
  `mark_tab_bar_dirty`.)
- `focus_watcher.py` shrinks to `on_program_status_change` plus the desktop
  notification, which is the one job nothing else in kitty does. The 2-second
  poll and the `agent_state` publishing go.
- `window-list`, `next-agent` and `advise` read `program_status` from
  `kitten @ ls` instead of session files, which ends the "keep the copies in
  step" problem for everything that has a record.
- The session-file fallback still has to live somewhere for windows with no
  record (older Claude Code, idle records dropped at a prompt). Either the
  watcher keeps publishing `agent_state` for those windows only, or the
  fallback is repeated in `tab_bar.py` and the shell tools. Decide in step 2,
  once step 1 shows how often the fallback is actually used.
- `seen_at` stays while `tidy-windows` uses it for idle time.

## Out of scope / follow-ups

- `{tab.program_status}` in `tab_title_template`. `tab_bar.py` already draws
  richer markers from `agent_state`; replacing it would lose the colours and
  the bold handling. Revisit only if the field proves useful on its own. (Step
  2 above reads the status from `tab_bar.py`'s Python instead.)
- The shell tools reading `program_status` is step 2, not part of step 1.

## Implementation notes

- kitty caches a watcher by path and never unloads one (see
  `retire_older_copies` in `focus_watcher.py`). Adding a callback is a changed
  file, so it needs the next `agent_watcherN.py` symlink and a `watcher` line
  update in `kitty.conf`, as before.
- The poll reads records straight off the window: `window.program_status` is a
  `kitty.program_status.ProgramStatus` and `window.program_status.as_list()`
  returns the same list of dicts that `on_program_status_change` gets in
  `data['program_status']` (verified in kitty 0.50.0 with a throwaway watcher:
  `[{'id': '', 'state': 'working', 'kind': None, 'progress': None, 'app': ...,
  'title': '', 'msg': ''}]`). It exists on every window, so windows created
  before the watcher loaded work too, and no cache is needed. It is an
  internal name, not documented API: read it with `getattr(window,
  'program_status', None)` and treat any exception as "no records", so a
  rename in a later kitty falls back to the session file. `ProgramStatus` also
  has `most_urgent`, `records` and `app_for`; use `as_list()` and our own
  mapping so the ranking stays in this repo's hands.
- Honour the existing rule that unknown or malformed input means "no state",
  never an exception.

## Tests

`kitty/tests` (kitty's Python, as the existing watcher tests):

- `state_from_records`: empty list; one record each of `working`, `blocked`,
  `done`, `idle`; mixed `blocked`+`working` -> `blocked`; `done`+`working` ->
  `done`; records from another app only -> empty; malformed record -> empty.
- Publish: a status change sets `agent_state` and notifies once on
  `blocked`/`done` when not looked at, not when looked at.
- Fallback: with no `claude-code` record the session-file path still decides;
  with one, the poll leaves the window alone.
- Cache cleared on window close.

Manual check in a scratch kitty (`--config=NONE -o allow_remote_control=socket-only
--listen-on unix:/tmp/<short>.sock`; the scratchpad path is too long for a
unix socket): run `claude` with a prompt needing permission outside the
scratchpad, confirm `working` -> `blocked` -> approve -> `done`, then focus
the window and confirm `done` clears and the marker follows.
