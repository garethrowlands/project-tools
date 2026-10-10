"""Tab title for kitty: a marker for Claude Code agents, then a short title.

kitty calls `draw_title` for `{custom}` in the tab title template; it draws the
title too, so it replaces `{title}` in kitty.conf:

    tab_title_template "{fmt.fg.red}{bell_symbol}{activity_symbol}{fmt.fg.tab}{custom}"

A tab gets one marker for the agents in its windows — the most pressing of
red `!` (one is blocked on you), green `✓` (one has finished since you last
looked) and yellow `…` (one is working) — or nothing. The states are the
`agent_state` user vars that focus_watcher.py keeps up to date.

A title that is a path keeps its last directory whole and cuts the ones above
it to their first letter, fish style, dropping all but the nearest few:
`github.com/garethrowlands/project-tools` is `g/g/project-tools`, and
`/Users/gareth/worktrees/project-tools/fix-tabs` is `…/w/p/fix-tabs`.
"""

from typing import Any

from kitty.fast_data_types import get_boss

# most pressing first: (states, marker, colour)
MARKERS = (
    (('blocked',), '!', 'red'),
    (('done',), '✓', 'green'),
    (('working',), '…', 'yellow'),
)


# how many directories above the last one keep their first letter
MAX_ANCESTORS = 2


def short_title(title: str) -> str:
    if '/' not in title:
        return title
    *ancestors, name = title.rstrip('/').split('/')
    if not name:
        return title
    root = ''
    if ancestors and not ancestors[0]:
        root, ancestors = '/', ancestors[1:]
    if len(ancestors) > MAX_ANCESTORS:
        root, ancestors = '…/', ancestors[-MAX_ANCESTORS:]
    # a hidden directory keeps its dot: .config is .c
    initials = (a[:2] if a.startswith('.') else a[:1] for a in ancestors)
    return root + ''.join(f'{i}/' for i in initials) + name


def marker(data: dict[str, Any]) -> str:
    try:
        tab = get_boss().tab_for_id(data['tab_id'])
        states = {window.user_vars.get('agent_state') for window in tab} if tab else set()
        fg = data['fmt'].fg
        for wanted, symbol, colour in MARKERS:
            if states.intersection(wanted):
                return f'{getattr(fg, colour)}{symbol} {fg.tab}'
    except Exception:
        pass
    return ''


def draw_title(data: dict[str, Any]) -> str:
    return marker(data) + short_title(str(data.get('title', '')))
