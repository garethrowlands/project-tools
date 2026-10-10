"""Tab title marker for Claude Code agents.

kitty calls `draw_title` for `{custom}` in the tab title template; put it at
the front in kitty.conf:

    tab_title_template "{custom}{fmt.fg.red}{bell_symbol}{activity_symbol}{fmt.fg.tab}{title}"

A tab gets one marker for the agents in its windows — the most pressing of
red `!` (one is blocked on you), green `✓` (one has finished since you last
looked) and yellow `…` (one is working) — or nothing. The states are the
`agent_state` user vars that focus_watcher.py keeps up to date.
"""

from typing import Any

from kitty.fast_data_types import get_boss

# most pressing first: (states, marker, colour)
MARKERS = (
    (('blocked',), '!', 'red'),
    (('done',), '✓', 'green'),
    (('working',), '…', 'yellow'),
)


def draw_title(data: dict[str, Any]) -> str:
    try:
        tab = get_boss().tab_for_id(data['tab_id'])
        states = {window.user_vars.get('agent_state') for window in tab} if tab else set()
        fg = data['fmt'].fg
        for wanted, marker, colour in MARKERS:
            if states.intersection(wanted):
                return f'{getattr(fg, colour)}{marker} {fg.tab}'
    except Exception:
        pass
    return ''
