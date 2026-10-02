"""Tests for open_local.py, hint_menu.py and open-actions.conf.

Run with kitty's bundled Python (the kittens import kitty internals):

    kitty +launch kitty/tests/test_kittens.py

Uses kitty's default options (not your kitty.conf) and temporary directories.
kitty's window/boss objects are replaced with small fakes; screen rendering is
checked by feeding the menu's output into a real kitty Screen. Exits 1 if any
test fails.
"""

import importlib.util
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from urllib.parse import quote, unquote, urlparse

from kitty.config import load_config
from kitty.fast_data_types import Screen, set_options

set_options(load_config())

import kitty.launch  # noqa: E402
import kitty.utils  # noqa: E402
import kitty.window as kw  # noqa: E402
from kitty.launch import parse_launch_args  # noqa: E402
from kitty.open_actions import actions_for_url_from_list, load_actions_from_path  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.dirname(HERE)
failures = 0


def check(name: str, cond: object, detail: object = '') -> None:
    global failures
    if not cond:
        failures += 1
    print('PASS' if cond else 'FAIL', name, '' if cond else detail)


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, os.path.join(SRC, f'{name}.py'))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def parse_bytes(screen: Screen, data: bytes) -> None:
    # The same helper kitty's own test suite uses to feed a Screen.
    view = memoryview(data)
    while view:
        dest = screen.test_create_write_buffer()
        n = screen.test_commit_write_buffer(view, dest)
        view = view[n:]
        screen.test_parse_written_data()


def rgb_of(color: int):
    # kitty stores truecolour cells as (r << 24 | g << 16 | b << 8 | 2)
    return ((color >> 24) & 255, (color >> 16) & 255, (color >> 8) & 255) if (color & 255) == 2 else None


ol, hm = load('open_local'), load('hint_menu')
launched: list = []
opened: list = []
kitty.launch.launch = lambda boss, opts, cmd: launched.append((opts, cmd))
kitty.utils.open_url = lambda url, *a, **kw: opened.append(url)
ol.log_error = lambda *a: None

tmp = os.path.realpath(tempfile.mkdtemp(prefix='kitty-links-test-'))


def f(*parts: str) -> str:
    return os.path.join(tmp, *parts)


for d in ('dir with space', '12#frag', '12', 'q?x', 'vault/sub', 'cwd/sub dir', 'cwd/playground'):
    os.makedirs(f(d), exist_ok=True)
for name, data in {
    "it's #1 ü.md": b'# hi\n', 'vault/sub/n.md': b'x\n', 'code.py': b'l1\nl2\n', 'd.json': b'{"a":1}\n',
    'trunc-utf8.txt': b'caf\xc3', 'empty': b'', 'img.png': b'\x89PNG\r\n\x1a\n\0\0',
    'doc.pdf': b'%PDF-1.7\n%\xe2\xe3\xcf\xd3\n', "cwd/it's v1.2.md": b'x', 'cwd/sub dir/a.py': b'x',
    'cwd/$(touch PWNED) ü.md': b'x',
}.items():
    with open(f(name), 'wb') as fh:
        fh.write(data)
registry = f('obsidian.json')
with open(registry, 'w') as fh:
    json.dump({'vaults': {'v': {'path': f('vault')}}}, fh)
ol.OBSIDIAN_REGISTRY = registry


class FakeScreen:
    def __init__(self, main: bool) -> None:
        self.main = main

    def is_main_linebuf(self) -> bool:
        return self.main


class FakeChild:
    def __init__(self, pids) -> None:
        self.foreground_processes = [{'pid': p} for p in pids]


class FakeWindow:
    def __init__(self, prompt=True, main=True, fg=(100,), user_vars=None, cwd=tmp) -> None:
        self.id = 7
        self.child_is_remote = False
        self.screen = FakeScreen(main)
        self.at_prompt = prompt
        self.user_vars = {'kitty_cd_link_pid': '100'} if user_vars is None else user_vars
        self.child = FakeChild(fg)
        self.cwd_of_child = cwd
        self.written = None
        self.pasted: list = []

    def write_to_child(self, data: str) -> None:
        self.written = data

    def paste_text(self, text: str) -> None:
        self.pasted.append(text)


class FakeBoss:
    def __init__(self, window) -> None:
        self.window_id_map = {7: window}
        self.errors: list = []
        self.combined: list = []
        self.kittens: list = []
        self.urls: list = []

    def show_error(self, title: str, msg: str) -> None:
        self.errors.append((title, msg))

    def combine(self, action: str, window_for_dispatch=None) -> None:
        self.combined.append(action)

    def run_kitten_with_metadata(self, name, args, window=None, custom_callback=None) -> None:
        self.kittens.append((name, args, custom_callback))

    def open_url(self, url: str) -> None:
        self.urls.append(url)


def click(url: str, window=None):
    """Run open_local the way open-actions.conf does; return (window, launched cmd, launch opts)."""
    window = window or FakeWindow()
    launched.clear()
    opened.clear()
    ol.handle_result(['open_local.py', unquote(urlparse(url).path), url], None, 7, FakeBoss(window))
    opts, cmd = launched[0] if launched else (None, None)
    return window, cmd, opts


def enc(path: str) -> str:
    return 'file://' + quote(path)


def payload_path(written: str) -> str:
    return bytes.fromhex(written[len(ol.TRIGGER):-1]).decode()


# --- open-actions.conf routing -------------------------------------------
acts = load_actions_from_path(os.path.join(SRC, 'open-actions.conf'))
for url in (enc(f('dir with space')), enc(f('code.py')) + '#2', enc(f("it's #1 ü.md")), 'file://' + f('q?x')):
    a = next(actions_for_url_from_list(url, acts), None)
    check(f'open-actions routes {url[-20:]!r} to open_local', a and a.func == 'kitten' and a.args[0] == 'open_local.py', a)
check('open-actions leaves https links alone', next(actions_for_url_from_list('https://example.com/', acts), None) is None)

# --- open_local: directories ----------------------------------------------
w, cmd, _ = click(enc(f('dir with space')))
check('dir at zsh prompt -> cd payload, no overlay', w.written and payload_path(w.written) == f('dir with space') and cmd is None)
check('cd payload is pure hex between trigger and BEL', w.written and re.fullmatch(r'[0-9a-f]+', w.written[len(ol.TRIGGER):-1]))
for why, win in [('full-screen program', FakeWindow(main=False)), ('not at prompt', FakeWindow(prompt=False)),
                 ('other foreground process', FakeWindow(fg=(300,))), ('handler not loaded', FakeWindow(user_vars={}))]:
    w, cmd, _ = click(enc(f('dir with space')), win)
    check(f'dir, {why} -> yazi overlay', w.written is None and cmd == ['yazi', f('dir with space')], cmd)
w, cmd, _ = click('file://' + f('12#frag'))
check("eza raw '12#frag' (sibling '12' exists) -> cd to 12#frag", w.written and payload_path(w.written) == f('12#frag'))
w, cmd, _ = click('file://' + f('q?x'))
check("eza raw 'q?x' -> cd to q?x", w.written and payload_path(w.written) == f('q?x'))

# --- open_local: files ----------------------------------------------------
w, cmd, opts = click(enc(f('code.py')) + '#2')
check('file#2 -> micro +2', cmd == ['micro', f('code.py'), '+2'], cmd)
check('overlay pinned to the clicked pane, its cwd and env', opts and opts.type == 'overlay' and opts.cwd == 'current'
      and opts.copy_env and opts.source_window == 'id:7' and opts.next_to == 'id:7', opts)
w, cmd, opts = click('file://' + f("it's #1 ü.md").replace(' ', '%20').replace('ü', '%C3%BC'))
check("eza raw \"it's #1 ü.md\" -> glow, not a line link", cmd == ['glow', '--tui', f("it's #1 ü.md")], cmd)
check('glow overlay carries the note path user var', opts and opts.var == [f"kitty_md_path={f(chr(105) + chr(116) + chr(39) + 's #1 ü.md')}"], opts and opts.var)
for name, prog in [('d.json', 'micro'), ('trunc-utf8.txt', 'micro'), ('empty', 'micro'), ('img.png', 'yazi'), ('doc.pdf', 'yazi')]:
    w, cmd, _ = click(enc(f(name)))
    check(f'{name} -> {prog}', cmd == [prog, f(name)], cmd)
w, cmd, _ = click(enc(f('missing.txt')))
check('missing file -> nothing opened', cmd is None and not opened)
w, cmd, opts = click(enc(f('code.py')), FakeWindow(user_vars={'kitty_cd_link_pid': '100', 'kitty_editor': 'micro'}))
check("overlay gets EDITOR/VISUAL from the shell's user var", opts and opts.env == ['EDITOR=micro', 'VISUAL=micro'], opts and opts.env)

# --- open_local: o in glow -> Obsidian ------------------------------------
for path, in_vault in [(f('vault/sub/n.md'), True), (f("it's #1 ü.md"), False)]:
    boss = FakeBoss(FakeWindow(user_vars={'kitty_md_path': path}))
    opened.clear()
    ol.handle_result(['open_local.py', '--obsidian'], None, 7, boss)
    if in_vault:
        check('o on a vault note -> obsidian://open with the exact path', opened and unquote(opened[0].split('path=', 1)[1]) == path, opened)
    else:
        check('o outside a vault -> error shown, nothing opened', not opened and boss.errors)
opts, cmd = parse_launch_args(['--type=overlay', '--copy-env', '--env', 'EDITOR=x', '--var', 'kitty_md_path=/a b=c.md', '--', 'glow', '/a b=c.md'])
check("kitty's parse_launch_args accepts the overlay arguments", opts.var == ['kitty_md_path=/a b=c.md'] and cmd[-1] == '/a b=c.md')

# --- hint_menu: rendering -------------------------------------------------
LINES, COLS = 12, 60
src = Screen(None, LINES, COLS)
parse_bytes(src, ('\x1b[34mplayground\x1b[m  notes.md  \x1b[1;38;2;255;200;0mgold\x1b[m \x1b[41mredbg\x1b[m\r\n'
                  "'my notes'  it's ü 日本.md\r\n" + 'x' * 75 + '\r\n\x1b[38;5;196mc196\x1b[m \x1b[7mrev\x1b[m').encode())
screen_ansi = kw.as_text(src, as_ansi=True, add_wrap_markers=True)
check('screen rows == screen lines', len(hm.screen_rows(screen_ansi)) == LINES)
FG, BG, BLUE, RED = (220, 220, 220), (20, 20, 20), (90, 140, 250), (200, 50, 50)
colors = {'fg': FG, 'bg': BG, 4: BLUE, 1: RED}


def faded(c):
    return tuple(round(a + (b - a) * hm.DIM_STRENGTH) for a, b in zip(c, BG))


out = Screen(None, LINES, COLS)
parse_bytes(out, hm.render(screen_ansi, LINES, COLS, colors).encode())
shown = kw.as_text(out).split('\n')
check('content redrawn in place', shown[0].startswith('playground  notes.md  gold redbg') and shown[1].startswith("'my notes'  it's ü 日本.md")
      and shown[2] == 'x' * 60 and shown[4].startswith('c196 rev'), shown[:5])
check('legend on the bottom lines, within width', ' cancel' in shown[-1] and all(len(row) <= COLS for row in shown), shown[-3:])


def cell(y: int, x: int):
    return out.line(y).cursor_from(x)  # re-fetch: Screen.line() reuses one Line object


check('palette colour faded towards the background', rgb_of(cell(0, 0).fg) == faded(BLUE), rgb_of(cell(0, 0).fg))
check('default foreground faded', rgb_of(cell(0, 12).fg) == faded(FG), rgb_of(cell(0, 12).fg))
check('truecolour faded, bold kept', rgb_of(cell(0, 22).fg) == faded((255, 200, 0)) and cell(0, 22).bold, rgb_of(cell(0, 22).fg))
check('background colour faded', rgb_of(cell(0, 27).bg) == faded(RED), rgb_of(cell(0, 27).bg))
check('256-colour faded via the colour cube', rgb_of(cell(4, 0).fg) == faded((255, 0, 0)), rgb_of(cell(4, 0).fg))
check('reverse video kept', cell(4, 5).reverse)
check('legend keys bold reverse, not dimmed', cell(LINES - 1, 1).bold and cell(LINES - 1, 1).reverse and rgb_of(cell(LINES - 1, 1).fg) is None)
check('links in the copy are not clickable', not out.hyperlinks_as_set())
out2 = Screen(None, LINES, COLS)
parse_bytes(out2, hm.render(screen_ansi, LINES, COLS, {}).encode())
check('no theme colours known -> faint fallback', out2.line(0).cursor_from(0).dim)
for cols in (30, 80, 200):
    widths = [len(re.sub(r'\x1b\[[0-9;]*m', '', row)) for row in hm.legend_lines(cols)]
    check(f'legend fills exactly {cols} columns', all(w == cols for w in widths), widths)

# --- hint_menu: colour replies and keys -----------------------------------
buf = (b'\x1b]4;4;rgb:5a5a/8c8c/fafa\x1b\\p\x1b]4;1;rgb:c8/32/32\x07\x1b]10;rgb:dcdc/dcdc/dcdc\x1b\\'
       b'\x1b]11;rgb:1414/1414/1414\x1b\\\x1b[?62;cf')
got, typed = hm.parse_color_replies(buf)
check('colour replies parsed (ST and BEL, 2- and 4-digit hex)', got == {4: BLUE, 1: RED, 'fg': FG, 'bg': BG}, got)
check('keys typed during the query are kept', typed == b'pf', typed)
check('query asks palette, fg, bg, then DA1', hm.color_query({0, 4}) == b'\x1b]4;0;?\x1b\\\x1b]4;4;?\x1b\\\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b[c')
for key, expect in [('p', 'p'), ('P', 'p'), ('\x1b', ''), ('\x03', ''), ('q', ''), ('z', None), ('\r', None)]:
    check(f'key {key!r} -> {expect!r}', hm.choice_for_key(key) == expect)

# --- hint_menu: actions ---------------------------------------------------
boss = FakeBoss(FakeWindow())
hm.handle_result([], 'f', 7, boss)
check('f -> stock insert-path hints', boss.combined == ['kitten hints --type path --program -'], boss.combined)
boss = FakeBoss(FakeWindow())
hm.handle_result([], '', 7, boss)
check('cancel -> nothing', not boss.combined and not boss.kittens)

cwd = f('cwd')
names = ["it's v1.2.md", '$(touch PWNED) ü.md', 'playground', 'sub dir']
boss = FakeBoss(FakeWindow(cwd=cwd))
hm.handle_result([], 'm', 7, boss)
name, args, done = boss.kittens[-1]
check('m -> multi-select hyperlink hints', name == 'hints' and args == ['--type=hyperlink', '--multiple'])
done({'match': [enc(os.path.join(cwd, n)) for n in names] + ['', 'file://otherhost/x', 'https://example.com/']}, 7, boss)
inserted = boss.window_id_map[7].pasted[0]
readback = subprocess.run(['zsh', '-fc', f'cd {shlex.quote(cwd)} && print -rl -- {inserted}'], capture_output=True, text=True).stdout.splitlines()
check('inserted paths are relative, quoted, and read back exactly by zsh', readback == names, (inserted, readback))
check('no command in a file name was run', not os.path.exists(os.path.join(cwd, 'PWNED')))
check('url_to_path: rg link with #LINE', hm.url_to_path(enc(f('code.py')) + '#2') == f('code.py'))
check('url_to_path: other host skipped', hm.url_to_path('file://otherhost' + f('code.py')) == '')
check('display_path: cwd itself -> .', hm.display_path(cwd, cwd) == '.')

for letter, hint_type, match, groups, expect in [
    ('o', '--type=path', 'sub dir/a.py', {}, ['micro', os.path.join(cwd, 'sub dir', 'a.py')]),
    ('n', '--type=linenum', 'sub dir/a.py:3', {'path': 'sub dir/a.py', 'line': '3'}, ['micro', os.path.join(cwd, 'sub dir', 'a.py'), '+3']),
]:
    boss = FakeBoss(FakeWindow(cwd=cwd))
    hm.handle_result([], letter, 7, boss)
    name, args, done = boss.kittens[-1]
    done({'match': [match], 'groupdicts': [groups]}, 7, boss)
    url = boss.urls[0] if boss.urls else ''
    action = next(actions_for_url_from_list(url, acts), None) if url else None
    launched.clear()
    if action:
        ol.handle_result(list(action.args), None, 7, FakeBoss(FakeWindow()))
    check(f'{letter} -> {hint_type} hints, then the click rules open {expect[0]}', args == [hint_type] and launched and launched[0][1] == expect,
          (args, url, launched))

print(f'\n{failures} failure(s)' if failures else '\nALL OK')
sys.exit(1 if failures else 0)
