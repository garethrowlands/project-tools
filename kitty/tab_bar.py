"""Tab title for kitty: a short title, and under it (in a vertical tab bar) what the tab is doing.

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

With `tab_bar_edge left` and `tab_title_max_lines 2` the marker leads the
second line, in front of the Claude session title (`agent_title`, also from
focus_watcher.py) of the agent it stands for, and `+N` for the tab's other
agents; a tab with no agent shows the command running in its windows there
instead. In a horizontal bar, where kitty drops everything after the first
line, the marker doesn't show at all.

The activity symbol (`tab_activity_symbol`, in red) is kitty's, but only for
windows without an agent: Claude Code repaints when it loses focus, which kitty
counts as activity, so a tab of agents would always show it. Agents have their
marker instead. The symbol stays on the first line, with the bell.

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
    (('error',), '✗', 'red'),
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


def state_marker(data: dict[str, Any], state: str) -> str:
    # the marker for one agent's state: bold, in the state's colour, then back to
    # the tab's own; '' for idle, which gets none, as in the window picker
    try:
        fmt = data['fmt']
        fg = fmt.fg
        for wanted, symbol, colour in MARKERS:
            if state in wanted:
                nobold = '' if tab_is_bold(fg) else fmt.nobold
                return f'{fmt.bold}{getattr(fg, colour)}{symbol}{nobold}{fg.tab}'
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


# every agent state, most pressing first: the order of the agents' lines
PRESSING = ('blocked', 'error', 'done', 'working', 'idle')


def option(name: str, default: int) -> int:
    try:
        return int(getattr(get_options(), name))
    except Exception:
        return default


def cut(text: str, room: int) -> str:
    # kitty cuts a line that is too long itself, but leaves a stray last
    # character after the ellipsis, and takes a +N with it: cut it here
    if room > 0 and len(text) > room:
        return text[:max(room - 1, 1)].rstrip() + '…'
    return text


def shell_name(window: Any) -> str:
    # what the window's foreground process is called: the shell, for one at a prompt
    try:
        return str(window.child.foreground_processes[-1]['cmdline'][0]).rsplit('/', 1)[-1].lstrip('-')
    except Exception:
        return ''


def program_entries(tab: Any) -> list[tuple[str, str, str]]:
    # what the windows that aren't agents are running: the command, as typed
    # (shell integration reports it), else the process's name, which for a shell
    # at a prompt is the shell's. Commands first, the tab's active window's first
    # of them, then the windows at a prompt.
    active = getattr(tab, 'active_window', None)
    entries = []
    for window in sorted(tab, key=lambda w: (bool(getattr(w, 'at_prompt', True)), w is not active)):
        if window.user_vars.get('agent_state'):
            continue
        command = ''
        if not getattr(window, 'at_prompt', True):
            command = ' '.join(str(getattr(window, 'last_cmd_cmdline', '') or '').split())
        command = command or shell_name(window)
        if command:
            entries.append(('', command, 'program'))
    return entries


def agent_entries(data: dict[str, Any], tab: Any) -> list[tuple[str, str, str]]:
    # (marker, session title, 'agent') of each agent in the tab, the most
    # pressing first and, of equals, the most recently changed. An agent with no
    # title yet shows what you last asked in it (`agent_hint`), in the same colour,
    # in quotes so as not to be taken for a name; with neither, it is just the
    # marker, or for an idle one the word "claude", so that it still shows that it is there.
    agents = []
    for window in tab:
        state = window.user_vars.get('agent_state')
        if state:
            rank = PRESSING.index(state) if state in PRESSING else len(PRESSING)
            at = float(window.user_vars.get('agent_state_at') or '0')
            title = str(window.user_vars.get('agent_title') or '')
            hint = str(window.user_vars.get('agent_hint') or '')
            agents.append((rank, -at, state, title, hint))
    agents.sort(key=lambda a: a[:2])
    entries = []
    for _, _, state, title, hint in agents:
        mark = state_marker(data, state)
        if title:
            entries.append((mark, title, 'agent'))
        elif hint:
            entries.append((mark, f'\u201c{hint}', 'agent'))
        elif state == 'idle':
            entries.append((mark, 'claude', 'program'))
        else:
            entries.append((mark, '', 'agent'))
    return entries


def status_lines(data: dict[str, Any]) -> list[str]:
    # what a vertical tab (tab_title_max_lines 2 or more) says below its title:
    # a line for each agent, the most pressing first: its marker (! ✓ …) then
    # its Claude session title, in the dim colour like every line but the
    # first; just the marker until the session has a title, else a quote of what
    # was last asked in it. Then a line for each command running in a
    # window that isn't an agent. When there are more than there are lines, the
    # last says how many more ("+3 more"); with a single line, it is the most
    # pressing agent's, and "+N" for its other agents. No lines, so the tab
    # stays one, when there is nothing to say. No indent: under tab_bar_style
    # separator the first line has none either.
    tab = get_boss().tab_for_id(data['tab_id'])
    if not tab:
        return []
    slots = max(1, option('tab_title_max_lines', 2) - 1)
    limit = option('tab_title_max_length', 0)
    agents = agent_entries(data, tab)
    entries = agents + program_entries(tab)
    if not entries:
        return []
    more = 0
    suffix = ''
    if slots == 1:
        if entries[0][2] == 'agent' and entries[0][1] and len(agents) > 1:
            suffix = f' +{len(agents) - 1}'
        shown = entries[:1]
    elif len(entries) > slots:
        shown = entries[:slots - 1]
        more = len(entries) - len(shown)
    else:
        shown = entries
    # the marker's cell is kept on every line, so that the text starts in the same
    # column whatever the state, and wherever a marker turns up
    pad = ' '
    dim, plain = dim_colour(data)
    lines = []
    for mark, text, kind in shown:
        prefix = mark or pad
        # a marker, or the pad that stands in for one, is one cell wide
        text = cut(text, limit - (1 if prefix else 0) - len(suffix) if limit > 0 else 0)
        lines.append(f'{prefix}{dim}{text}{suffix}{plain}' if text else mark)
    if more:
        lines.append(f'{pad}{dim}+{more} more{plain}')
    return lines


def status_line(data: dict[str, Any]) -> str:
    try:
        return '\n'.join(status_lines(data))
    except Exception:
        return ''


def draw_title(data: dict[str, Any]) -> str:
    title = activity(data) + short_title(str(data.get('title', '')), *dim_colour(data))
    second = status_line(data)
    return f'{title}\n{second}' if second else title
