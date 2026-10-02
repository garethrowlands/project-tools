"""Cmd+P: show a menu of hint modes over the current pane, then run the one picked.

Mapped in links.conf as:
    map kitty_mod+p kitten hint_menu.py

kitty cannot make an overlay translucent, so the menu fakes it: it redraws the
pane's screen, dimmed, and puts a one- or two-line key legend at the bottom.

Most choices run kitty's stock hints kitten. p and m are custom: they label
the hyperlinks in the pane (eza --hyperlink, rg --hyperlink-format=kitty, ...)
and insert the chosen files' paths at the prompt, quoted for the shell and
relative to the shell's directory when inside it.
"""

import os
import re
import shlex
import sys
from typing import Any
from urllib.parse import unquote

from kittens.tui.handler import result_handler

# (letter, legend label, action)
CHOICES = (
    ('p', 'path', ''),
    ('m', 'paths…', ''),
    ('f', 'file in text', 'kitten hints --type path --program -'),
    ('o', 'open file', ''),
    ('w', 'word', 'kitten hints --type word --program -'),
    ('l', 'line', 'kitten hints --type line --program -'),
    ('h', 'hash', 'kitten hints --type hash --program -'),
    ('n', 'file:line→editor', ''),
    ('y', 'open link', 'kitten hints --type hyperlink'),
    ('c', 'choose file', 'kitten choose-files'),
    ('d', 'choose dir', 'kitten choose-files --mode=dir'),
)
# How far the pane's text fades towards the background behind the menu:
# 0 = not at all, 1 = invisible. (kitty's own "faint" is about 0.6.)
DIM_STRENGTH = 0.4

SGR = re.compile(r'\x1b\[([0-9;:]*)m')
OSC = re.compile(r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)')
Color = tuple[int, int, int]


def screen_rows(screen_ansi: str) -> list[str]:
    # screen-ansi input: every screen row ends in \r; a \n follows unless the
    # row soft-wraps into the next one.
    rows = screen_ansi.split('\r')
    if rows and rows[-1].strip('\n') == '':
        rows.pop()
    return [r[1:] if r.startswith('\n') else r for r in rows]


def faint(row: str) -> str:
    # Fallback when the theme colours are unknown: kitty's fixed-strength faint.
    row = OSC.sub('', row)
    return '\x1b[0;2m' + SGR.sub(lambda m: m.group(0) + '\x1b[2m', row) + '\x1b[m'


# Colour queries: palette entries (OSC 4), default fg/bg (OSC 10/11), then a
# device-attributes request whose reply marks the end of the answers.
OSC_COLOR_REPLY = re.compile(rb'\x1b\](?:4;(\d+)|(1[01]));rgb:([0-9a-fA-F]+)/([0-9a-fA-F]+)/([0-9a-fA-F]+)(?:\x07|\x1b\\)')
DA1_REPLY = re.compile(rb'\x1b\[\?[0-9;]*c')


def color_query(indices: set[int]) -> bytes:
    q = ''.join(f'\x1b]4;{i};?\x1b\\' for i in sorted(indices))
    return (q + '\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b[c').encode()


def parse_color_replies(buf: bytes) -> tuple[dict[Any, Color], bytes]:
    """Colours keyed by palette index, 'fg' and 'bg'; plus any other input
    (keys the user typed meanwhile)."""
    def channel(h: bytes) -> int:
        return int(h, 16) * 255 // (16 ** len(h) - 1)

    colors: dict[Any, Color] = {}
    for m in OSC_COLOR_REPLY.finditer(buf):
        key: Any = int(m.group(1)) if m.group(1) else ('fg' if m.group(2) == b'10' else 'bg')
        colors[key] = (channel(m.group(3)), channel(m.group(4)), channel(m.group(5)))
    return colors, DA1_REPLY.sub(b'', OSC_COLOR_REPLY.sub(b'', buf))


def indexed_colors_used(rows: list[str]) -> set[int]:
    ans = set(range(16))
    for params in SGR.findall('\n'.join(rows)):
        ans.update(int(n) for n in re.findall(r'[34]8[;:]5[;:](\d+)', params) if int(n) < 256)
    return ans


def update_colors(params: str, state: dict[str, Any]) -> None:
    # Track the current fg/bg as None (default), ('idx', n) or ('rgb', (r, g, b)).
    toks = params.split(';') if params else ['0']
    i = 0
    while i < len(toks):
        t = toks[i]
        if ':' in t:  # ITU forms: 38:5:n, 38:2::r:g:b, 38:2:r:g:b
            sub = t.split(':')
            if sub[0] in ('38', '48') and len(sub) > 2:
                which = 'fg' if sub[0] == '38' else 'bg'
                if sub[1] == '5' and sub[2].isdigit():
                    state[which] = ('idx', int(sub[2]))
                elif sub[1] == '2' and len(sub) >= 5 and all(x.isdigit() for x in sub[-3:]):
                    state[which] = ('rgb', tuple(int(x) for x in sub[-3:]))
            i += 1
            continue
        n = int(t) if t.isdigit() else 0
        if n == 0:
            state['fg'] = state['bg'] = None
        elif 30 <= n <= 37 or 90 <= n <= 97:
            state['fg'] = ('idx', n - 30 if n < 90 else n - 82)
        elif 40 <= n <= 47 or 100 <= n <= 107:
            state['bg'] = ('idx', n - 40 if n < 100 else n - 92)
        elif n in (39, 49):
            state['fg' if n == 39 else 'bg'] = None
        elif n in (38, 48) and i + 1 < len(toks):
            which = 'fg' if n == 38 else 'bg'
            if toks[i + 1] == '5' and i + 2 < len(toks):
                state[which] = ('idx', int(toks[i + 2] or 0))
                i += 2
            elif toks[i + 1] == '2' and i + 4 < len(toks):
                state[which] = ('rgb', tuple(int(x or 0) for x in toks[i + 2:i + 5]))
                i += 4
        i += 1


def resolve(spec: Any, default: Color, colors: dict[Any, Color]) -> Color:
    if spec is None:
        return default
    if spec[0] == 'rgb':
        return spec[1]
    n = spec[1]
    if n in colors:
        return colors[n]
    if 16 <= n < 232:  # standard 6x6x6 cube
        n -= 16
        return tuple(0 if v == 0 else 55 + 40 * v for v in (n // 36, n // 6 % 6, n % 6))  # type: ignore
    if 232 <= n < 256:
        g = 8 + 10 * (n - 232)
        return (g, g, g)
    return default


def blend(c: Color, bg: Color, s: float) -> str:
    return ';'.join(str(round(a + (b - a) * s)) for a, b in zip(c, bg))


def dimmed(row: str, colors: dict[Any, Color]) -> str:
    """The row with every colour faded DIM_STRENGTH of the way to the
    background; other attributes (bold, italic, reverse, ...) kept."""
    fg, bg = colors['fg'], colors['bg']
    state: dict[str, Any] = {'fg': None, 'bg': None}

    def override() -> str:
        ans = f'\x1b[38;2;{blend(resolve(state["fg"], fg, colors), bg, DIM_STRENGTH)}m'
        if state['bg'] is not None:
            ans += f'\x1b[48;2;{blend(resolve(state["bg"], bg, colors), bg, DIM_STRENGTH)}m'
        return ans

    def sub(m: 're.Match[str]') -> str:
        update_colors(m.group(1), state)
        return m.group(0) + override()

    row = OSC.sub('', row)
    return '\x1b[0m' + override() + SGR.sub(sub, row) + '\x1b[m'


def legend_lines(cols: int) -> list[str]:
    # Items like ' p  path ', key in bold reverse video, wrapped to the width.
    items = [(letter, label) for letter, label, _ in CHOICES] + [('esc', 'cancel')]
    lines: list[tuple[str, int]] = [('', 0)]
    for key, label in items:
        text, width = f'\x1b[1;7m {key} \x1b[22;27m {label} ', len(key) + len(label) + 4
        cur, cur_width = lines[-1]
        if cur_width and cur_width + width > cols:
            lines.append((text, width))
        else:
            lines[-1] = (cur + text, cur_width + width)
    return [text + ' ' * max(0, cols - width) for text, width in lines]


def render(screen_ansi: str, lines: int, cols: int, colors: dict[Any, Color]) -> str:
    legend = legend_lines(cols)
    out = ['\x1b[?25l\x1b[?7l\x1b[H\x1b[2J']  # hide cursor, no autowrap, clear
    have_theme = 'fg' in colors and 'bg' in colors
    for y, row in enumerate(screen_rows(screen_ansi)[:lines]):
        out.append(f'\x1b[{y + 1};1H{dimmed(row, colors) if have_theme else faint(row)}')
    for i, text in enumerate(legend):
        out.append(f'\x1b[{lines - len(legend) + i + 1};1H\x1b[m{text}\x1b[m')
    return ''.join(out)


def choice_for_key(ch: str) -> str | None:
    """A menu letter, '' to cancel, or None to keep waiting."""
    if ch in ('\x1b', '\x03', '\x04', 'q'):
        return ''
    ch = ch.lower()
    return ch if any(ch == letter for letter, _, _ in CHOICES) else None


def ask_terminal_colors(fd: int, indices: set[int], timeout: float = 0.5) -> tuple[dict[Any, Color], bytes]:
    import select
    import time

    os.write(fd, color_query(indices))
    buf, deadline = b'', time.monotonic() + timeout
    while not DA1_REPLY.search(buf):
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([fd], [], [], remaining)[0]:
            break
        buf += os.read(fd, 65536)
    if not DA1_REPLY.search(buf):
        return {}, b''  # no complete answer: dim with faint instead
    return parse_color_replies(buf)


def main(args: list[str]) -> str:
    import termios
    import tty

    screen_ansi = sys.stdin.read()
    with open('/dev/tty', 'r+b', buffering=0) as term:
        fd = term.fileno()
        size = os.get_terminal_size(fd)
        old = termios.tcgetattr(term)
        try:
            tty.setraw(term)
            # The overlay uses the same theme as the pane it covers.
            colors, typed = ask_terminal_colors(fd, indexed_colors_used(screen_rows(screen_ansi)))
            os.write(fd, render(screen_ansi, size.lines, size.columns, colors).encode('utf-8'))
            while True:
                # A lone ESC byte is the Esc key; longer ESC sequences are
                # arrow keys or late terminal replies, so ignore them.
                if not (typed.startswith(b'\x1b') and len(typed) > 1):
                    for ch in typed.decode('latin-1'):
                        answer = choice_for_key(ch)
                        if answer is not None:
                            return answer
                typed = os.read(fd, 64)
                if not typed:
                    return ''
        finally:
            termios.tcsetattr(term, termios.TCSADRAIN, old)


def url_to_path(url: str) -> str:
    from urllib.parse import urlparse

    from kitty.utils import get_hostname

    if not url.startswith('file://'):
        return ''
    rest = url[len('file://'):]
    host, sep, raw = rest.partition('/')
    if host.partition(':')[0] not in ('', 'localhost', get_hostname()):
        return ''  # a file on another machine (e.g. ls over ssh)
    # eza leaves '#' and '?' in names unescaped, so try the whole raw path
    # first; rg's links carry a real '#LINE' fragment, so then try without it.
    whole = unquote(sep + raw, errors='surrogateescape')
    if os.path.exists(whole):
        return whole
    path = unquote(urlparse(url).path, errors='surrogateescape')
    return path if os.path.exists(path) else ''


def display_path(path: str, cwd: str) -> str:
    if cwd and os.path.isabs(cwd):
        if path == cwd:
            return '.'
        if os.path.commonpath([path, cwd]) == cwd:
            return os.path.relpath(path, cwd)
    return path


def insert_link_paths(boss: Any, window: Any, multiple: bool) -> None:
    args = ['--type=hyperlink'] + (['--multiple'] if multiple else [])

    def done(data: dict[str, Any], target_window_id: int, boss: Any) -> None:
        w = boss.window_id_map.get(target_window_id)
        if w is None:
            return
        cwd = w.cwd_of_child or ''
        paths = [p for p in (url_to_path(m) for m in data.get('match') or () if m) if p]
        if paths:
            w.paste_text(' '.join(shlex.quote(display_path(p, cwd)) for p in paths))

    boss.run_kitten_with_metadata('hints', args, window=window, custom_callback=done)


def open_found_path(boss: Any, window: Any, with_line: bool) -> None:
    # Stock hints would open a path with macOS `open` (TextEdit) and type
    # `$EDITOR +LINE path` into the shell; instead hand the match to kitty as a
    # file:// link, so open-actions.conf (open_local.py) opens it in a TUI.
    from urllib.parse import quote

    def done(data: dict[str, Any], target_window_id: int, boss: Any) -> None:
        w = boss.window_id_map.get(target_window_id)
        if w is None:
            return
        if with_line:
            from kittens.hints.main import linenum_process_result

            path, line = linenum_process_result(data)
        else:
            path, line = next((m for m in data.get('match') or () if m), ''), 0
        if not path:
            return
        path = os.path.join(w.cwd_of_child or data.get('cwd') or '/', os.path.expanduser(path))
        if os.path.exists(path):
            boss.open_url('file://' + quote(os.path.abspath(path)) + (f'#{line}' if line > 0 else ''))

    args = ['--type=linenum'] if with_line else ['--type=path']
    boss.run_kitten_with_metadata('hints', args, window=window, custom_callback=done)


@result_handler(type_of_input='screen-ansi')
def handle_result(args: list[str], answer: str, target_window_id: int, boss: Any) -> None:
    window = boss.window_id_map.get(target_window_id)
    if window is None or not answer:
        return
    if answer in ('p', 'm'):
        insert_link_paths(boss, window, multiple=answer == 'm')
    elif answer in ('o', 'n'):
        open_found_path(boss, window, with_line=answer == 'n')
    else:
        action = next((a for letter, _, a in CHOICES if letter == answer), '')
        if action:
            boss.combine(action, window_for_dispatch=window)
