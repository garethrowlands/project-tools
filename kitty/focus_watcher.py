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

2. Works out the agent state of every window running `claude` — blocked, error,
   working, done or idle — and publishes it as the window's `agent_state`
   user var (and, as `agent_state_at`, the epoch second it last changed, which
   next-agent orders by): when the window's program status changes, when its focus
   changes, and every POLL_SECONDS for the windows that don't report one. When a state changes it redraws the tab
   bar (tab_bar.py turns the var into a tab marker; the window's Claude session title goes with it as `agent_title`, for the second line of a vertical tab) and, if the agent got
   blocked or finished in a window you aren't looking at, sends a desktop
   notification that focuses that window when clicked.

The state comes first from the window's Program Status Protocol (OSC 7501)
records, which Claude Code (2.1.295 and later) sends once the terminal answers
its startup query, and which kitty 0.50 keeps on `window.program_status`:
`status_state` picks the most pressing of the `claude-code` records. kitty
itself keeps `done` until you focus the window or press a key, so it needs no
`seen_at`. A window with no such record — an older Claude Code, or one whose
idle record kitty dropped at a prompt — falls back to Claude Code's
~/.claude*/sessions/<pid>.json, by the same rules as `_claude_session_state` in zsh/functions/claude-session.zsh, which the
window picker and next-agent use, and `agent_state` in
python/tidy-windows-advise/advise — keep the three in step. That file is
undocumented internal state, so anything missing or malformed means "no
state", never an error.
"""

import json
import os
import time
from glob import escape as glob_escape
from glob import glob
from typing import Any

POLL_SECONDS = 2.0
STATUS_APP = 'claude-code'
# most pressing first: the state a window gets when its records hold several
STATUS_ORDER = ('blocked', 'error', 'done', 'working', 'idle')
NOTIFY = {'blocked': 'Claude needs you', 'error': 'Claude failed', 'done': 'Claude finished'}

# window id -> the agent state last published for it
published: dict[int, str] = {}
# window id -> the session title last published for it
published_title: dict[int, str] = {}
# transcript path -> (bytes read so far, last ai-title in them): a transcript
# only grows, so each poll reads what was appended since the last
title_cache: dict[str, tuple[int, str]] = {}
# window id -> (at a prompt, last command) last seen for it, for redrawing the
# tab bar's program line when it changes
program_seen: dict[int, tuple[bool, str]] = {}
# window id -> the last-prompt hint last published for it
published_hint: dict[int, str] = {}
# transcript path -> (size when read, last prompt in it)
prompt_cache: dict[str, tuple[int, str]] = {}
# how much of a transcript's end is read to find its last prompt, doubling
# until found, up to the cap
PROMPT_TAIL = 64 * 1024
PROMPT_TAIL_MAX = 4 * 1024 * 1024
HINT_LENGTH = 100
# a prompt shorter than this ("yes") doesn't say which session it is
HINT_MIN_LENGTH = 12
timer_started = False


def session_file(pid: int) -> str:
    """The session file of a claude process, searching every config dir (a
    process started with CLAUDE_CONFIG_DIR set uses that dir, not ~/.claude).
    Should two dirs have one for this pid, the newest is the live process's."""
    paths = glob(os.path.expanduser(f'~/.claude*/sessions/{pid}.json'))
    return max(paths, key=os.path.getmtime) if paths else ''


def read_session(path: str) -> dict[str, Any]:
    try:
        with open(path) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def last_ai_title(transcript: str) -> str:
    """The last `{"type":"ai-title","aiTitle":...}` line of a transcript. The
    title is regenerated as the conversation goes on, so it is the last that
    counts; only the lines added since the previous call are parsed."""
    try:
        size = os.path.getsize(transcript)
        offset, title = title_cache.get(transcript, (0, ''))
        if size < offset:
            offset, title = 0, ''
        if size == offset:
            return title
        with open(transcript, 'rb') as f:
            f.seek(offset)
            data = f.read(size - offset)
        # a line still being written has no newline yet: leave it for next time
        complete = data[:data.rfind(b'\n') + 1]
        for line in complete.splitlines():
            if b'"ai-title"' not in line:
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if entry.get('type') == 'ai-title' and isinstance(entry.get('aiTitle'), str) and entry['aiTitle']:
                title = entry['aiTitle']
        title_cache[transcript] = (offset + len(complete), title)
        return title
    except Exception:
        return ''


def prompt_in(data: bytes, whole: bool) -> tuple[str, str]:
    """The last prompts in the end of a transcript, from its
    `{"type":"last-prompt","lastPrompt":...}` lines: (the last that is long
    enough to say which session it is, the last of any length), each '' if
    there is none. Commands (`/clear`, a `<command-name>` entry) are not prompts.
    A prompt is collapsed to one line. The first line of a partial read may be
    cut short, so it is left out."""
    lines = data.split(b'\n')
    if not whole:
        lines = lines[1:]
    last = ''
    for line in reversed(lines):
        if b'"last-prompt"' not in line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        prompt = entry.get('lastPrompt') if entry.get('type') == 'last-prompt' else None
        if not isinstance(prompt, str):
            continue
        prompt = ' '.join(prompt.split())[:HINT_LENGTH]
        if not prompt or prompt[0] in '/<':
            continue
        last = last or prompt
        if len(prompt) >= HINT_MIN_LENGTH:
            return prompt, last
    return '', last


def last_prompt(transcript: str) -> str:
    """What you last asked in a session: it says which session is which until
    it has a title. A reply like "yes" doesn't, so it is the last prompt of
    HINT_MIN_LENGTH characters or more, or failing that the last of any length.
    Read from the end of the transcript, which is only looked at again when it
    has grown."""
    try:
        size = os.path.getsize(transcript)
        cached = prompt_cache.get(transcript)
        if cached and cached[0] == size:
            return cached[1]
        tail, found, last = PROMPT_TAIL, '', ''
        with open(transcript, 'rb') as f:
            while True:
                start = max(0, size - tail)
                f.seek(start)
                found, last = prompt_in(f.read(size - start), start == 0)
                if found or start == 0 or tail >= PROMPT_TAIL_MAX:
                    break
                tail *= 2
        prompt = found or last
        prompt_cache[transcript] = (size, prompt)
        return prompt
    except Exception:
        return ''


def session_title(path: str, seen: tuple[str, ...] = ()) -> str:
    """The title of the Claude session whose sessions/<pid>.json is `path`, by
    the same rules as `_claude_session_title` in zsh/functions/claude-session.zsh
    and `claude_session_name` in python/tidy-windows-advise/advise - keep the
    three in step, except that this one has no "name" slug to fall back on (a
    tab bar line of `context-37` says nothing) and puts a name you gave the
    session (`nameSource` "user") first: that, else its own ai-title, else
    (parked on a background job) the job's title by the same rule, else ''.
    Undocumented internal state, so anything missing means ''."""
    data = read_session(path)
    # a name you gave it yourself (/rename) beats any generated title; one Claude
    # Code derived at startup (`nameSource` "derived") is only a slug
    name = data.get('name')
    if data.get('nameSource') == 'user' and isinstance(name, str) and name:
        return name
    config_dir = os.path.dirname(os.path.dirname(path))
    session_id = data.get('sessionId')
    if isinstance(session_id, str) and session_id:
        found = glob(os.path.join(glob_escape(config_dir), 'projects', '*', f'{glob_escape(session_id)}.jsonl'))
        title = last_ai_title(found[0]) if found else ''
        if title:
            return title
    job_id = data.get('parkedJobId')
    if isinstance(job_id, str) and job_id and path not in seen:
        for other in glob(os.path.join(glob_escape(config_dir), 'sessions', '*.json')):
            if other != path and read_session(other).get('jobId') == job_id:
                title = session_title(other, seen + (path,))
                if title:
                    return title
                break
    return ''


def window_title(window: Any) -> str:
    pid = claude_pid(window)
    path = session_file(pid) if pid else ''
    return session_title(path) if path else ''


def window_hint(window: Any) -> str:
    """The last prompt of the window's session, for telling it apart before it
    has a title."""
    pid = claude_pid(window)
    path = session_file(pid) if pid else ''
    session_id = read_session(path).get('sessionId') if path else None
    if not (isinstance(session_id, str) and session_id):
        return ''
    config_dir = os.path.dirname(os.path.dirname(path))
    found = glob(os.path.join(glob_escape(config_dir), 'projects', '*', f'{glob_escape(session_id)}.jsonl'))
    return last_prompt(found[0]) if found else ''


def agent_state(status: str, since: float, seen_at: str, looked_at: bool) -> str:
    """`status` and `since` (epoch seconds of its last change) are the session
    file's; `seen_at` is the window's user var, '' if it has none."""
    if status == 'waiting':
        return 'blocked'
    if status == 'busy':
        return 'working'
    # 'shell': undocumented; a session sits in it once its turn has finished
    if status in ('idle', 'shell'):
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


def status_state(records: Any) -> str:
    """The agent state in a window's program status records (a list of dicts
    with `app` and `state`), the most pressing one of Claude Code's, or ''.
    `msg` and `title` can hold commands and paths, so they are never read."""
    try:
        states = {r['state'] for r in records if r['app'] == STATUS_APP}
        return next((s for s in STATUS_ORDER if s in states), '')
    except Exception:
        return ''


def status_records(window: Any) -> list[Any]:
    """kitty's `window.program_status` is internal, not documented, so a kitty
    without it, or that has renamed it, just means no records."""
    try:
        return window.program_status.as_list()
    except Exception:
        return []


def window_state(window: Any, looked_at: bool) -> str:
    state = status_state(status_records(window))
    if state:
        return state
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
    """Publishes the window's agent state, the title of its session and, while
    it has none, what you last asked in it, if any of them has changed."""
    state = window_state(window, looked_at)
    title = window_title(window) if state else ''
    hint = window_hint(window) if state and not title else ''
    state_changed = state != published.get(window.id, '')
    # None for a window not seen before, so its title is checked even if it is '':
    # a var left by an older copy of this watcher may still be there
    title_changed = title != published_title.get(window.id)
    hint_changed = hint != published_hint.get(window.id)
    if not (state_changed or title_changed or hint_changed):
        return
    redraw = state_changed
    if state_changed:
        published[window.id] = state
        window.set_user_var('agent_state', state or None)
        # when it changed: next-agent goes to the most recent first
        window.set_user_var('agent_state_at', str(int(time.time())) if state else None)
    for value, cache, changed, var in ((title, published_title, title_changed, 'agent_title'),
                                       (hint, published_hint, hint_changed, 'agent_hint')):
        if changed:
            cache[window.id] = value
            if value != (window.user_vars.get(var) or ''):
                window.set_user_var(var, value or None)
                redraw = True
    if redraw:
        tab_manager = boss.os_window_map.get(window.os_window_id)
        if tab_manager is not None:
            tab_manager.mark_tab_bar_dirty()
    if state_changed and state in NOTIFY and not looked_at:
        notify(boss, window, state)


def refresh_program(boss: Any, window: Any) -> None:
    """Redraws the tab bar when what a window is running changes: kitty draws
    the tab on a title change, before it has been told the command, and not
    again when the command finishes, so tab_bar.py's line for the program
    would be a step behind. Agents' windows don't have one."""
    seen = (bool(getattr(window, 'at_prompt', True)), str(getattr(window, 'last_cmd_cmdline', '') or ''))
    before = program_seen.get(window.id)
    program_seen[window.id] = seen
    if before is None or before == seen or window.user_vars.get('agent_state'):
        return
    tab_manager = boss.os_window_map.get(window.os_window_id)
    if tab_manager is not None:
        tab_manager.mark_tab_bar_dirty()


def poll(boss: Any) -> None:
    windows = list(boss.all_windows)
    for window in windows:
        try:
            refresh(boss, window, is_looked_at(boss, window))
            refresh_program(boss, window)
        except Exception:
            pass
    live = {window.id for window in windows}
    for window_id in [i for i in program_seen if i not in live]:
        del program_seen[window_id]
    for window_id in [i for i in published if i not in live]:
        del published[window_id]
    for window_id in [i for i in published_title if i not in live]:
        del published_title[window_id]
    for window_id in [i for i in published_hint if i not in live]:
        del published_hint[window_id]


def retire_older_copies() -> None:
    """kitty caches a watcher by path and never unloads one, so a changed copy
    of this file only gets loaded under a new name, alongside the old one —
    whose timer would go on publishing states by its old rules, and sending
    its own notifications. Its poll becomes a no-op, and the focus events of
    the windows it is attached to are served by this copy."""
    from kitty.launch import watcher_modules
    for module in list(watcher_modules.values()):
        older = getattr(module.get('poll'), '__globals__', None)
        if older is None or older is globals() or 'published' not in older:
            continue
        older['poll'] = lambda boss: None
        older['refresh'] = refresh


def start_timer() -> None:
    global timer_started
    if timer_started:
        return
    retire_older_copies()
    from kitty.fast_data_types import add_timer, get_boss
    add_timer(lambda *a: poll(get_boss()), POLL_SECONDS, True)
    timer_started = True


def on_load(*args: Any) -> None:
    start_timer()


def on_program_status_change(boss: Any, window: Any, data: dict[str, Any]) -> None:
    # straight away, so a ! or ✓ shows as it happens rather than at the next poll
    try:
        refresh(boss, window, is_looked_at(boss, window))
        start_timer()
    except Exception:
        pass


def on_focus_change(boss: Any, window: Any, data: dict[str, Any]) -> None:
    window.set_user_var('seen_at', str(int(time.time())))
    # straight away, so a ✓ clears as you arrive rather than at the next poll
    try:
        refresh(boss, window, bool(data.get('focused')))
        start_timer()
    except Exception:
        pass
