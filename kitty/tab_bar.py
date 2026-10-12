"""Tab title for kitty: a marker for Claude Code agents, then a short title.

kitty calls `draw_title` for `{custom}` in the tab title template; it draws the
activity symbol and the title too, so it replaces `{activity_symbol}` and
`{title}` in kitty.conf:

    tab_title_template "{fmt.fg.red}{bell_symbol}{fmt.fg.tab}{activity_symbol * 0}{custom}"

`{activity_symbol * 0}` draws nothing, and has to be there: kitty puts its own
activity symbol in front of any template that doesn't name the field, which
would show it for agents after all, and twice for other windows.

A tab gets one marker for the agents in its windows — the most pressing of
red `!` (one is blocked on you), green `✓` (one has finished since you last
looked) and yellow `…` (one is working) — or nothing, in bold. The states are
the `agent_state` user vars that focus_watcher.py keeps up to date.

The activity symbol (`tab_activity_symbol`, in red) is kitty's, but only for
windows without an agent: Claude Code repaints when it loses focus, which kitty
counts as activity, so a tab of agents would always show it. Agents have their
marker instead.

A title that is a path keeps its last directory whole and cuts the ones above
it to their first letter, fish style, dropping all but the nearest few:
`github.com/garethrowlands/project-tools` is `g/g/project-tools`, and
`/Users/gareth/worktrees/project-tools/fix-tabs` is `…/w/p/fix-tabs`. That
`…/` is drawn dimmer than the title, to tell it from the working marker.
"""

from typing import Any

from kitty.fast_data_types import get_boss, get_options
from kitty.tab_bar import color_from_int

# most pressing first: (states, marker, colour)
MARKERS = (
    (('blocked',), '!', 'red'),
    (('done',), '✓', 'green'),
    (('working',), '…', 'yellow'),
)


# how many directories above the last one keep their first letter
MAX_ANCESTORS = 2


def short_title(title: str, dim: str = '', plain: str = '') -> str:
    # `dim` and `plain` are the colour codes around the mark for dropped directories
    if '/' not in title:
        return title
    *ancestors, name = title.rstrip('/').split('/')
    if not name:
        return title
    root = ''
    if ancestors and not ancestors[0]:
        root, ancestors = '/', ancestors[1:]
    if len(ancestors) > MAX_ANCESTORS:
        root, ancestors = f'{dim}…/{plain}', ancestors[-MAX_ANCESTORS:]
    # a hidden directory keeps its dot: .config is .c
    initials = (a[:2] if a.startswith('.') else a[:1] for a in ancestors)
    return root + ''.join(f'{i}/' for i in initials) + name


def tab_is_bold(fg: Any) -> bool:
    # whether the tab being drawn has a bold title anyway (kitty's default for the active tab)
    try:
        opts = get_options()
        return (opts.active_tab_font_style if fg.tab_data.is_active else opts.inactive_tab_font_style)[0]
    except Exception:
        return False


def marker(data: dict[str, Any]) -> str:
    try:
        tab = get_boss().tab_for_id(data['tab_id'])
        states = {window.user_vars.get('agent_state') for window in tab} if tab else set()
        fmt = data['fmt']
        fg = fmt.fg
        for wanted, symbol, colour in MARKERS:
            if states.intersection(wanted):
                nobold = '' if tab_is_bold(fg) else fmt.nobold
                return f'{fmt.bold}{getattr(fg, colour)}{symbol} {nobold}{fg.tab}'
    except Exception:
        pass
    return ''


def dim_colour(data: dict[str, Any]) -> tuple[str, str]:
    # the tab's text colour, halfway to its background; then back to the text colour
    try:
        fg = data['fmt'].fg
        text = color_from_int(fg.draw_data.tab_fg(fg.tab_data))
        back = color_from_int(fg.draw_data.tab_bg(fg.tab_data))
        mixed = ((getattr(text, c) + getattr(back, c)) // 2 for c in ('red', 'green', 'blue'))
        return getattr(fg, '_' + ''.join(f'{v:02x}' for v in mixed)), fg.tab
    except Exception:
        return '', ''


def activity(data: dict[str, Any]) -> str:
    try:
        symbol = get_options().tab_activity_symbol
        tab = get_boss().tab_for_id(data['tab_id'])
        if symbol and tab and any(
                w.has_activity_since_last_focus and not w.user_vars.get('agent_state') for w in tab):
            fg = data['fmt'].fg
            return f'{fg.red}{symbol}{fg.tab}'
    except Exception:
        pass
    return ''


def draw_title(data: dict[str, Any]) -> str:
    return activity(data) + marker(data) + short_title(str(data.get('title', '')), *dim_colour(data))
