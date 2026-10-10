"""Global kitty watcher: tracks when you last looked at each window, and what
the Claude Code agent in it is doing.

Enable in kitty.conf (kitty loads it once, at startup):

    watcher focus_watcher.py

Two jobs:

1. Stamps each window's `seen_at` user var (wall-clock epoch seconds) both when
   it gains focus and when it loses it, so `kitty @ ls` shows it under
   `user_vars`. kitty's own `last_focused_at` only records the gain, which
   can't tell "the agent finished while I was watching" from "it finished
   after I left". (Focus events only reach windows created after the watcher
   was loaded.)

2. Every POLL_SECONDS, works out the agent state of every window running
   `claude` — blocked, working, shell, done or idle — and publishes it as the
   window's `agent_state` user var. When a state changes it redraws the tab
   bar (tab_bar.py turns the var into a tab marker) and, if the agent got
   blocked or finished in a window you aren't looking at, sends a desktop
   notification that focuses that window when clicked.

The state comes from Claude Code's ~/.claude*/sessions/<pid>.json, by the same
rules as `_claude_session_state` in zsh/functions/claude-session.zsh, which the
window picker and next-agent use — keep the two in step. That file is
undocumented internal state, so anything missing or malformed means "no
state", never an error.
"""

import json
import os
import time
from glob import glob
from typing import Any

POLL_SECONDS = 2.0
NOTIFY = {'blocked': 'Claude needs you', 'done': 'Claude finished'}

# window id -> the agent state last published for it
published: dict[int, str] = {}
timer_started = False


def session_file(pid: int) -> str:
    """The session file of a claude process, searching every config dir (a
    process started with CLAUDE_CONFIG_DIR set uses that dir, not ~/.claude).
    Should two dirs have one for this pid, the newest is the live process's."""
    paths = glob(os.path.expanduser(f'~/.claude*/sessions/{pid}.json'))
    return max(paths, key=os.path.getmtime) if paths else ''


def agent_state(status: str, since: float, seen_at: str, looked_at: bool) -> str:
    """`status` and `since` (epoch seconds of its last change) are the session
    file's; `seen_at` is the window's user var, '' if it has none."""
    if status == 'waiting':
        return 'blocked'
    if status == 'busy':
        return 'working'
    if status == 'shell':
        return 'shell'
    if status == 'idle':
        if seen_at.isdigit() and not looked_at and since > int(seen_at):
            return 'done'
        return 'idle'
    return ''


def claude_pid(window: Any) -> int:
    """The pid of the window's frontmost foreground process if that is `claude`
    right now, else 0. Session files outlive their process and pids get
    reused, so a state is only ever read for a live claude."""
    try:
        process = window.child.foreground_processes[-1]
        name = os.path.basename((process['cmdline'] or [''])[0].lstrip('-'))
        return int(process['pid']) if name == 'claude' else 0
    except Exception:
        return 0


def window_state(window: Any, looked_at: bool) -> str:
    pid = claude_pid(window)
    path = session_file(pid) if pid else ''
    if not path:
        return ''
    try:
        with open(path) as f:
            session = json.load(f)
        return agent_state(str(session.get('status', '')), float(session.get('statusUpdatedAt', 0)) / 1000,
                           str(window.user_vars.get('seen_at', '')), looked_at)
    except Exception:
        return ''


def is_looked_at(boss: Any, window: Any) -> bool:
    from kitty.fast_data_types import current_focused_os_window_id
    return boss.active_window is window and window.os_window_id == current_focused_os_window_id()


def notify(boss: Any, window: Any, state: str) -> None:
    tab = window.tabref()
    where = [tab.effective_title if tab else '', os.path.basename(window.cwd_of_child or '')]
    manager = boss.notification_manager
    cmd = manager.create_notification_cmd()
    cmd.title = NOTIFY[state]
    cmd.body = ' › '.join(x for x in where if x)
    window_id = window.id
    cmd.on_activation = lambda *a: boss.set_active_window(window_id, switch_os_window_if_needed=True)
    manager.notify_with_command(cmd, window_id)


def refresh(boss: Any, window: Any, looked_at: bool) -> None:
    """Publishes the window's agent state if it has changed."""
    state = window_state(window, looked_at)
    if state == published.get(window.id, ''):
        return
    published[window.id] = state
    window.set_user_var('agent_state', state or None)
    tab_manager = boss.os_window_map.get(window.os_window_id)
    if tab_manager is not None:
        tab_manager.mark_tab_bar_dirty()
    if state in NOTIFY and not looked_at:
        notify(boss, window, state)


def poll(boss: Any) -> None:
    windows = list(boss.all_windows)
    for window in windows:
        try:
            refresh(boss, window, is_looked_at(boss, window))
        except Exception:
            pass
    live = {window.id for window in windows}
    for window_id in [i for i in published if i not in live]:
        del published[window_id]


def start_timer() -> None:
    global timer_started
    if timer_started:
        return
    from kitty.fast_data_types import add_timer, get_boss
    add_timer(lambda *a: poll(get_boss()), POLL_SECONDS, True)
    timer_started = True


def on_load(*args: Any) -> None:
    start_timer()


def on_focus_change(boss: Any, window: Any, data: dict[str, Any]) -> None:
    window.set_user_var('seen_at', str(int(time.time())))
    # straight away, so a ✓ clears as you arrive rather than at the next poll
    try:
        refresh(boss, window, bool(data.get('focused')))
        start_timer()
    except Exception:
        pass
