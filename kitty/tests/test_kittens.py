"""Tests for open_local.py, hint_menu.py, open-actions.conf, focus_watcher.py and tab_bar.py.

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
import time
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
check("eza raw \"it's #1 ü.md\" -> mdfried, not a line link", cmd == ['mdfried', f("it's #1 ü.md")], cmd)
check('mdfried overlay carries the note path user var', opts and opts.var == [f"kitty_md_path={f(chr(105) + chr(116) + chr(39) + 's #1 ü.md')}"], opts and opts.var)
for name, prog in [('d.json', 'micro'), ('trunc-utf8.txt', 'micro'), ('empty', 'micro'), ('img.png', 'yazi'), ('doc.pdf', 'yazi')]:
    w, cmd, _ = click(enc(f(name)))
    check(f'{name} -> {prog}', cmd == [prog, f(name)], cmd)
w, cmd, _ = click(enc(f('missing.txt')))
check('missing file -> nothing opened', cmd is None and not opened)
w, cmd, opts = click(enc(f('code.py')), FakeWindow(user_vars={'kitty_cd_link_pid': '100', 'kitty_editor': 'micro'}))
check("overlay gets EDITOR/VISUAL from the shell's user var", opts and opts.env == ['EDITOR=micro', 'VISUAL=micro'], opts and opts.env)

# --- open_local: file references (path:line[:col]) found by detect_url_regex ---
def click_ref(ref: str, cwd: str = tmp):
    window = FakeWindow(cwd=cwd)
    launched.clear()
    opened.clear()
    ol.handle_result(['open_local.py', '--ref', ref], None, 7, FakeBoss(window))
    opts, cmd = launched[0] if launched else (None, None)
    return window, cmd, opts


os.makedirs(f('proj/src/deep'), exist_ok=True)
for name in ('proj/src/main.go', 'proj/src/deep/x.py', 'proj/README.md'):
    with open(f(name), 'wb') as fh:
        fh.write(b'x\n')
for ref, cwd, want in [
    ('code.py:2', tmp, (f('code.py'), 2, 0)),
    ('./code.py:2:5', tmp, (f('code.py'), 2, 5)),
    (f('code.py') + ':7', '/', (f('code.py'), 7, 0)),
    ('src/main.go:10:3', f('proj'), (f('proj/src/main.go'), 10, 3)),
    ('src/main.go:10', f('proj/src/deep'), (f('proj/src/main.go'), 10, 0)),   # found in a parent of the cwd
    ('main.go:10', f('proj/src'), (f('proj/src/main.go'), 10, 0)),
    ('missing.py:3', tmp, ('', 0, 0)),
    ('code.py', tmp, ('', 0, 0)),
    ('code.py:x', tmp, ('', 0, 0)),
    ('example.com:443', tmp, ('', 0, 0)),
]:
    check(f'resolve_ref({ref!r} in {os.path.relpath(cwd, tmp) if cwd.startswith(tmp) else cwd}) -> {want[1:]}', ol.resolve_ref(ref, cwd) == want, ol.resolve_ref(ref, cwd))
w, cmd, opts = click_ref('code.py:2')
check('file ref -> ide at that line', cmd == ['ide', f('code.py') + ':2'], cmd)
check('ide runs in the background, from the clicked pane, with its environment', opts and opts.type == 'background'
      and opts.cwd == 'current' and opts.copy_env and opts.source_window == 'id:7', opts)
w, cmd, _ = click_ref('code.py:2:5')
check('file ref with a column -> ide path:line:col', cmd == ['ide', f('code.py') + ':2:5'], cmd)
w, cmd, _ = click_ref('main.go:10', f('proj/src'))
check('file ref is resolved from the clicked window\'s cwd', cmd == ['ide', f('proj/src/main.go') + ':10'], cmd)
w, cmd, _ = click_ref('README.md:3', f('proj'))
check('a Markdown file ref goes to ide too', cmd == ['ide', f('proj/README.md') + ':3'], cmd)
w, cmd, _ = click_ref('dir with space:4')
check('a directory ref opens the directory, ignoring the line', w.written and payload_path(w.written) == f('dir with space'), (w.written, cmd))
w, cmd, _ = click_ref('missing.py:3')
check('a ref to nothing opens nothing', cmd is None and not opened and w.written is None)
errors = []
w = FakeWindow(cwd=tmp)
boss = FakeBoss(w)
ol.handle_result(['open_local.py', '--ref', 'missing.py:3'], None, 7, boss)
check('a ref to nothing says so, naming it and where it looked',
      len(boss.errors) == 1 and boss.errors[0][0] == 'No such file' and 'missing.py:3' in boss.errors[0][1] and tmp in boss.errors[0][1], boss.errors)

# open-actions.conf routes file references to --ref, and leaves real URLs alone
for ref in ('code.py:2', 'src/main.go:10:3', './a_b-c.test.ts:1', '~/x/y.rs:9', '/abs/p.zsh:12:1'):
    a = next(actions_for_url_from_list(ref, acts), None)
    check(f'open-actions routes the file reference {ref!r} to open_local --ref',
          a and a.func == 'kitten' and list(a.args[:2]) == ['open_local.py', '--ref'] and ref in ' '.join(a.args), a)
for url in ('https://example.com:8080/x.py:3', 'ssh://host:22', '192.168.1.1:8080', 'localhost:3000', 'a:3', 'code.py:'):
    a = next(actions_for_url_from_list(url, acts), None)
    check(f'open-actions does not take {url!r} for a file reference', a is None or '--ref' not in a.args, a)

# the detect_url_regex in links.conf (POSIX ERE, checked with grep -E) matches the same references
ere = next(line.split(None, 1)[1].strip() for line in open(os.path.join(SRC, 'links.conf')) if line.startswith('detect_url_regex '))
for text, want in [('code.py:2', 'code.py:2'), ('src/main.go:10:3: undefined', 'src/main.go:10:3'), ('see ./a_b-c.test.ts:1.', './a_b-c.test.ts:1'),
                   ('FAIL ~/x/y.rs:9:', '~/x/y.rs:9'), ('192.168.1.1:8080', ''), ('code.py: line', ''), ('plain words 12:30', '')]:
    got = subprocess.run(['grep', '-oE', ere], input=text, capture_output=True, text=True).stdout.strip()
    check(f'detect_url_regex on {text!r} -> {want!r}', got == want, got)

# --- open_local: o in mdfried -> Obsidian ------------------------------------
for path, in_vault in [(f('vault/sub/n.md'), True), (f("it's #1 ü.md"), False)]:
    boss = FakeBoss(FakeWindow(user_vars={'kitty_md_path': path}))
    opened.clear()
    ol.handle_result(['open_local.py', '--obsidian'], None, 7, boss)
    if in_vault:
        check('o on a vault note -> obsidian://open with the exact path', opened and unquote(opened[0].split('path=', 1)[1]) == path, opened)
    else:
        check('o outside a vault -> error shown, nothing opened', not opened and boss.errors)
# --- open_local: w in mdfried -> wide view --------------------------------------
wide_path = f("it's #1 ü.md")
launched.clear()
ol.handle_result(['open_local.py', '--wide'], None, 7, FakeBoss(FakeWindow(user_vars={'kitty_md_path': wide_path})))
opts, cmd = launched[0] if launched else (None, None)
check('w -> sh overlay with the note path as an argument', cmd and cmd[:2] == ['sh', '-c'] and cmd[-1] == wide_path, cmd)
check('w: the path is never spliced into the script', cmd and wide_path not in cmd[2], cmd)
check('w: unwrapped glow into moor, moor alone as the fallback', cmd and 'glow -s dark -w 0' in cmd[2] and '| moor' in cmd[2] and 'else moor "$1"' in cmd[2], cmd)
check('w overlay is pinned like the others', opts and opts.type == 'overlay' and opts.source_window == 'id:7' and opts.next_to == 'id:7', opts)
launched.clear()
ol.handle_result(['open_local.py', '--wide'], None, 7, FakeBoss(FakeWindow(user_vars={})))
check('w without a note path -> nothing opened', not launched)
opts, cmd = parse_launch_args(['--type=overlay', '--copy-env', '--env', 'EDITOR=x', '--var', 'kitty_md_path=/a b=c.md', '--', 'mdfried', '/a b=c.md'])
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

# focus_watcher.py: seen_at is stamped on focus gain and on focus loss
fw = load('focus_watcher')
fw.timer_started = True  # no poll timer in the tests


class WatchedWindow:
    def __init__(self):
        self.user_vars = {}

    def set_user_var(self, key, val):
        self.user_vars[key] = val


for focused in (True, False):
    watched = WatchedWindow()
    before = int(time.time())
    fw.on_focus_change(None, watched, {'focused': focused})
    seen_at = watched.user_vars.get('seen_at', '')
    check(f'focus_watcher stamps seen_at on focus {"gain" if focused else "loss"}',
          seen_at.isdigit() and before <= int(seen_at) <= int(time.time()), watched.user_vars)

# focus_watcher.py: agent states, published as the agent_state user var
for status, since, seen_at, looked_at, want in [
    ('waiting', 2000, '1000', False, 'blocked'),
    ('busy', 2000, '1000', False, 'working'),
    ('shell', 2000, '1000', False, 'done'),
    ('shell', 2000, '3000', False, 'idle'),
    ('idle', 2000, '1000', False, 'done'),
    ('idle', 2000, '3000', False, 'idle'),
    ('idle', 2000, '', False, 'idle'),
    ('idle', 2000, '-', False, 'idle'),
    ('idle', 2000, '1000', True, 'idle'),
    ('thinking', 2000, '1000', False, ''),
]:
    got = fw.agent_state(status, since, seen_at, looked_at)
    check(f'agent_state: {status}, since {since}, seen_at {seen_at!r}, looked_at {looked_at} -> {want!r}', got == want, got)


class AgentWindow:
    def __init__(self, id, pid, proc='claude', seen_at='1000', cwd='/p/shop-api'):
        self.id, self.os_window_id, self.cwd_of_child = id, 1, cwd
        self.user_vars = {'seen_at': seen_at} if seen_at else {}
        self.child = type('Child', (), {'foreground_processes': [{'pid': 1, 'cmdline': ['-zsh']}, {'pid': pid, 'cmdline': [f'/usr/local/bin/{proc}']}]})()

    def set_user_var(self, key, val):
        if val is None:
            self.user_vars.pop(key, None)
        else:
            self.user_vars[key] = val

    def tabref(self):
        return type('Tab', (), {'effective_title': 'proj'})()


class AgentBoss:
    def __init__(self, *windows):
        self.all_windows, self.active_window = list(windows), None
        self.dirty, self.notified, self.focused = 0, [], []
        boss = self

        class TabManager:
            def mark_tab_bar_dirty(self):
                boss.dirty += 1

        class Notifications:
            def create_notification_cmd(self):
                return type('Cmd', (), {})()

            def notify_with_command(self, cmd, channel_id):
                boss.notified.append((channel_id, cmd.title, cmd.body, cmd.on_activation))

        self.os_window_map, self.notification_manager = {1: TabManager()}, Notifications()

    def set_active_window(self, window, switch_os_window_if_needed=False):
        self.focused.append((window, switch_os_window_if_needed))


def write_session(home, pid, status, since, config='.claude'):
    os.makedirs(os.path.join(home, config, 'sessions'), exist_ok=True)
    with open(os.path.join(home, config, 'sessions', f'{pid}.json'), 'w') as fh:
        json.dump({'pid': pid, 'status': status, 'statusUpdatedAt': since * 1000}, fh)


real_home, agent_home = os.environ.get('HOME'), os.path.realpath(tempfile.mkdtemp(prefix='kitty-agent-test-'))
os.environ['HOME'] = agent_home
fw.is_looked_at = lambda boss, window: boss.active_window is window

write_session(agent_home, 501, 'busy', 2000)
write_session(agent_home, 502, 'waiting', 2000, '.claude-k')
write_session(agent_home, 503, 'waiting', 2000)
check('session_file finds a session in another config dir', fw.session_file(502) == os.path.join(agent_home, '.claude-k', 'sessions', '502.json'), fw.session_file(502))
check('session_file: none for an unknown pid', fw.session_file(599) == '')
write_session(agent_home, 501, 'idle', 100, '.claude-k')
os.utime(os.path.join(agent_home, '.claude-k', 'sessions', '501.json'), (1, 1))
check('session_file: of two for one pid, the newer', fw.session_file(501) == os.path.join(agent_home, '.claude', 'sessions', '501.json'), fw.session_file(501))

a, b, c, d = AgentWindow(1, 501), AgentWindow(2, 502), AgentWindow(3, 503, proc='zsh'), AgentWindow(4, 599)
boss = AgentBoss(a, b, c, d)
boss.active_window = b
fw.poll(boss)
check('poll publishes each agent\'s state', (a.user_vars.get('agent_state'), b.user_vars.get('agent_state')) == ('working', 'blocked'), (a.user_vars, b.user_vars))
check('poll: a session file for a pid that isn\'t claude now is ignored', 'agent_state' not in c.user_vars, c.user_vars)
check('poll: claude with no session file has no state', 'agent_state' not in d.user_vars, d.user_vars)
check('poll redraws the tab bar once per change', boss.dirty == 2, boss.dirty)
check('poll: no notification for the window you are looking at', boss.notified == [], boss.notified)
fw.poll(boss)
check('poll: nothing changed, nothing redrawn', boss.dirty == 2, boss.dirty)

write_session(agent_home, 501, 'waiting', 2100)
fw.poll(boss)
check('poll: blocked elsewhere notifies, saying where', [n[:3] for n in boss.notified] == [(1, 'Claude needs you', 'proj › shop-api')], boss.notified)
fw.poll(boss)
check('poll: one notification per change', len(boss.notified) == 1, boss.notified)
boss.notified[0][3]()
check('clicking the notification focuses that window', boss.focused == [(1, True)], boss.focused)

write_session(agent_home, 501, 'idle', 2200)
fw.poll(boss)
check('poll: finished elsewhere is done, and notifies', a.user_vars.get('agent_state') == 'done' and boss.notified[-1][:2] == (1, 'Claude finished'), (a.user_vars, boss.notified))
boss.active_window = a
fw.on_focus_change(boss, a, {'focused': True})
check('focusing a done window makes it idle at once', a.user_vars.get('agent_state') == 'idle' and len(boss.notified) == 2, a.user_vars)

write_session(agent_home, 502, 'idle', 2300, '.claude-k')
boss.active_window = b
fw.poll(boss)
check('poll: finishing while you watch is idle, not done', b.user_vars.get('agent_state') == 'idle' and len(boss.notified) == 2, (b.user_vars, boss.notified))

a.child.foreground_processes[-1]['cmdline'] = ['/bin/zsh']
fw.poll(boss)
check('poll: the state goes when claude exits', 'agent_state' not in a.user_vars, a.user_vars)
with open(os.path.join(agent_home, '.claude-k', 'sessions', '502.json'), 'w') as fh:
    fh.write('not json')
fw.poll(boss)
check('poll: a malformed session file is no state', 'agent_state' not in b.user_vars, b.user_vars)
boss.all_windows = [b]
fw.poll(boss)
check('poll forgets closed windows', set(fw.published) == {2}, fw.published)


# focus_watcher.py: the Program Status Protocol (OSC 7501) records come first
def rec(state, app='claude-code'):
    return {'id': '', 'state': state, 'kind': None, 'progress': None, 'app': app, 'title': '', 'msg': ''}


class Status:
    def __init__(self, *records):
        self.records = list(records)

    def as_list(self):
        return self.records


for records, want in [
    ([], ''),
    ([rec('working')], 'working'),
    ([rec('blocked')], 'blocked'),
    ([rec('done')], 'done'),
    ([rec('idle')], 'idle'),
    ([rec('idle'), rec('working')], 'working'),
    ([rec('working'), rec('done')], 'done'),
    ([rec('done'), rec('blocked'), rec('working')], 'blocked'),
    ([rec('working', app='rsync')], ''),
    ([rec('blocked', app='rsync'), rec('idle')], 'idle'),
    ([rec('error')], 'error'),
    ([rec('error'), rec('done')], 'error'),
    ([rec('blocked'), rec('error')], 'blocked'),
    ([{'app': 'claude-code'}], ''),
    (['working'], ''),
    (None, ''),
]:
    got = fw.status_state(records)
    check(f'status_state: {[r["state"] if isinstance(r, dict) and "state" in r else r for r in records or []]} -> {want!r}', got == want, got)

write_session(agent_home, 521, 'waiting', 2000)
s1, s2, s3, s4 = (AgentWindow(i, p, proc=pr) for i, p, pr in [(11, 599, 'zsh'), (12, 521, 'claude'), (13, 599, 'zsh'), (14, 521, 'claude')])
s1.program_status = Status(rec('working'))
s2.program_status = Status(rec('working'))
s3.program_status = Status()
s4.program_status = Status()
boss = AgentBoss(s1, s2, s3, s4)
boss.active_window = s3
fw.poll(boss)
check('status: a window with a claude-code record has that state, claude process or not', s1.user_vars.get('agent_state') == 'working', s1.user_vars)
check('status: the record wins over the session file', s2.user_vars.get('agent_state') == 'working', s2.user_vars)
check('status: no records and no claude is no state', 'agent_state' not in s3.user_vars, s3.user_vars)
check('status: no records falls back to the session file', s4.user_vars.get('agent_state') == 'blocked', s4.user_vars)

boss.notified.clear()
s1.program_status.records = [rec('blocked')]
fw.on_program_status_change(boss, s1, {'program_status': s1.program_status.records})
check('status change: published at once, and notifies when you are not looking',
      s1.user_vars.get('agent_state') == 'blocked' and [n[:2] for n in boss.notified] == [(11, 'Claude needs you')], (s1.user_vars, boss.notified))
fw.on_program_status_change(boss, s1, {})
check('status change: nothing new, no second notification', len(boss.notified) == 1, boss.notified)

boss.active_window = s1
s1.program_status.records = [rec('done')]
fw.on_program_status_change(boss, s1, {})
check('status change: done in the window you are looking at is shown, without a notification',
      s1.user_vars.get('agent_state') == 'done' and len(boss.notified) == 1, (s1.user_vars, boss.notified))
s1.program_status.records = []
fw.on_program_status_change(boss, s1, {})
check('status change: kitty clearing the record clears the state', 'agent_state' not in s1.user_vars, s1.user_vars)

boss.active_window = s3
s1.program_status.records = [rec('done')]
fw.on_program_status_change(boss, s1, {})
check('status change: done elsewhere notifies', boss.notified[-1][:2] == (11, 'Claude finished'), boss.notified)

s2.program_status = type('Broken', (), {'as_list': lambda self: 1 / 0})()
s4.program_status = None
fw.poll(boss)
check('status: records that cannot be read fall back to the session file', s2.user_vars.get('agent_state') == 'blocked' and s4.user_vars.get('agent_state') == 'blocked', (s2.user_vars, s4.user_vars))
del s4.program_status
fw.poll(boss)
check('status: a kitty with no program_status attribute falls back too', s4.user_vars.get('agent_state') == 'blocked', s4.user_vars)

# agent_state_at: when the published state last changed, for next-agent's recency order
boss.active_window = s3
s1.program_status.records = [rec('working')]
fw.on_program_status_change(boss, s1, {})
first = s1.user_vars.get('agent_state_at')
check('state_at: stamped when the state changes', str(first).isdigit(), s1.user_vars)
fw.on_program_status_change(boss, s1, {})
check('state_at: untouched while the state stays', s1.user_vars.get('agent_state_at') == first, s1.user_vars)
s1.program_status.records = [rec('error')]
boss.notified.clear()
fw.on_program_status_change(boss, s1, {})
check('state_at: error is published and notifies', s1.user_vars.get('agent_state') == 'error' and [n[:2] for n in boss.notified] == [(11, 'Claude failed')], (s1.user_vars, boss.notified))
s1.program_status.records = []
fw.on_program_status_change(boss, s1, {})
check('state_at: cleared with the state', 'agent_state_at' not in s1.user_vars, s1.user_vars)

# agent_title: the Claude session's title, for the second line of a vertical tab
def write_titled_session(pid, session_id, status='busy', name=None, parked=None, job=None, config='.claude'):
    write_session(agent_home, pid, status, 3000, config)
    path = os.path.join(agent_home, config, 'sessions', f'{pid}.json')
    with open(path) as fh:
        data = json.load(fh)
    data.update({k: v for k, v in (('sessionId', session_id), ('name', name), ('parkedJobId', parked), ('jobId', job)) if v})
    with open(path, 'w') as fh:
        json.dump(data, fh)


def transcript(session_id, *lines, config='.claude', mode='w'):
    d = os.path.join(agent_home, config, 'projects', '-p-shop-api')
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, f'{session_id}.jsonl'), mode) as fh:
        for line in lines:
            fh.write(line)


def ai(title):
    return json.dumps({'type': 'ai-title', 'aiTitle': title}) + '\n'


user_line = json.dumps({'type': 'user', 'message': 'hi'}) + '\n'
t1 = AgentWindow(31, 531)
boss = AgentBoss(t1)
boss.active_window = t1
write_titled_session(531, 'sid531', name='shop-api-1a')
transcript('sid531', user_line, ai('First title'), user_line)
fw.poll(boss)
check('title: the last ai-title of the transcript is published', t1.user_vars.get('agent_title') == 'First title', t1.user_vars)
dirty = boss.dirty
fw.poll(boss)
check('title: nothing is redrawn while it stays', boss.dirty == dirty, (boss.dirty, dirty))
transcript('sid531', ai('Second title'), mode='a')
fw.poll(boss)
check('title: a regenerated title replaces it, state unchanged', t1.user_vars.get('agent_title') == 'Second title' and t1.user_vars.get('agent_state') == 'working', t1.user_vars)
check('title: a changed title redraws the tab bar', boss.dirty == dirty + 1, (boss.dirty, dirty))
transcript('sid531', ai('Third ti'), mode='a')
with open(os.path.join(agent_home, '.claude', 'projects', '-p-shop-api', 'sid531.jsonl'), 'a') as fh:
    fh.write('{"type": "ai-title", "aiTitle": "Half writ')
fw.poll(boss)
check('title: a line still being written is not read', t1.user_vars.get('agent_title') == 'Third ti', t1.user_vars)
with open(os.path.join(agent_home, '.claude', 'projects', '-p-shop-api', 'sid531.jsonl'), 'a') as fh:
    fh.write('ten"}\n')
fw.poll(boss)
check('title: it is read once complete', t1.user_vars.get('agent_title') == 'Half written', t1.user_vars)
transcript('sid531', ai('Fresh'), mode='w')
fw.poll(boss)
check('title: a transcript that shrinks is read again from the start', t1.user_vars.get('agent_title') == 'Fresh', t1.user_vars)

os.remove(os.path.join(agent_home, '.claude', 'projects', '-p-shop-api', 'sid531.jsonl'))
fw.poll(boss)
check('title: a session with no ai-title yet has none, not its slug', 'agent_title' not in t1.user_vars and t1.user_vars.get('agent_state') == 'working', t1.user_vars)

t2 = AgentWindow(32, 532)
boss.all_windows = [t1, t2]
write_titled_session(532, 'sid532', name='context-e1', parked='job1')
write_titled_session(9001, 'sidjob', name='Job name', job='job1')
transcript('sidjob', ai('Job title'))
fw.poll(boss)
check('title: a parked session shows its job\'s title', t2.user_vars.get('agent_title') == 'Job title', t2.user_vars)
transcript('sid532', ai('Own title'))
fw.poll(boss)
check('title: its own ai-title comes before the job\'s', t2.user_vars.get('agent_title') == 'Own title', t2.user_vars)

t4 = AgentWindow(34, 534)
boss.all_windows = [t1, t4]
write_titled_session(534, 'sid534', name='fluent modules review')
with open(os.path.join(agent_home, '.claude', 'sessions', '534.json')) as fh:
    named = json.load(fh)
named['nameSource'] = 'user'
with open(os.path.join(agent_home, '.claude', 'sessions', '534.json'), 'w') as fh:
    json.dump(named, fh)
transcript('sid534', ai('Generated title'))
fw.poll(boss)
check('title: a name you gave the session beats the generated title', t4.user_vars.get('agent_title') == 'fluent modules review', t4.user_vars)
named['name'] = 'renamed again'
with open(os.path.join(agent_home, '.claude', 'sessions', '534.json'), 'w') as fh:
    json.dump(named, fh)
fw.poll(boss)
check('title: and follows a rename', t4.user_vars.get('agent_title') == 'renamed again', t4.user_vars)
named['nameSource'] = 'derived'
with open(os.path.join(agent_home, '.claude', 'sessions', '534.json'), 'w') as fh:
    json.dump(named, fh)
fw.poll(boss)
check('title: a derived name is only a slug, so the generated title wins', t4.user_vars.get('agent_title') == 'Generated title', t4.user_vars)

t3 = AgentWindow(33, 599, proc='zsh')
t3.user_vars['agent_title'] = 'left by an older copy'
boss.all_windows = [t1, t3]
fw.poll(boss)
check('title: a window without claude has none, and a stale one is cleared', 'agent_title' not in t3.user_vars, t3.user_vars)
os.remove(os.path.join(agent_home, '.claude', 'sessions', '531.json'))
fw.poll(boss)
check('title: gone with the session', 'agent_title' not in t1.user_vars, t1.user_vars)
check('title: closed windows are forgotten', set(fw.published_title) <= {31, 33}, fw.published_title)

# agent_hint: what you last asked in a session, until it has a title
def lp(prompt):
    return json.dumps({'type': 'last-prompt', 'lastPrompt': prompt, 'sessionId': 'x'}) + '\n'


h1 = AgentWindow(41, 541)
boss = AgentBoss(h1)
boss.active_window = h1
write_titled_session(541, 'sid541', name='context-e1')
transcript('sid541', user_line, lp('which service owns the invoice?'), user_line, lp('/clear'), lp('And  ADR-0011?\nTersely.'))
fw.poll(boss)
check('hint: the last prompt, on one line', h1.user_vars.get('agent_hint') == 'And ADR-0011? Tersely.', h1.user_vars)
dirty = boss.dirty
fw.poll(boss)
check('hint: nothing is redrawn while it stays', boss.dirty == dirty, (boss.dirty, dirty))
transcript('sid541', lp('Now the second one'), mode='a')
fw.poll(boss)
check('hint: a new prompt replaces it and redraws', h1.user_vars.get('agent_hint') == 'Now the second one' and boss.dirty == dirty + 1, (h1.user_vars, boss.dirty, dirty))
transcript('sid541', lp('/clear'), lp('<command-name>/x</command-name>'), mode='a')
fw.poll(boss)
check('hint: commands are not prompts', h1.user_vars.get('agent_hint') == 'Now the second one', h1.user_vars)
transcript('sid541', lp('yes'), lp('ok'), mode='a')
fw.poll(boss)
check('hint: a short reply is skipped for the prompt before', h1.user_vars.get('agent_hint') == 'Now the second one', h1.user_vars)
transcript('sid541', ai('A real title'), mode='a')
fw.poll(boss)
check('hint: gone once the session has a title', 'agent_hint' not in h1.user_vars and h1.user_vars.get('agent_title') == 'A real title', h1.user_vars)

h2 = AgentWindow(42, 542)
boss.all_windows = [h2]
write_titled_session(542, 'sid542', name='context-e2')
transcript('sid542', lp('buried prompt'), *([json.dumps({'type': 'assistant', 'message': 'x' * 500}) + '\n'] * 600))
fw.poll(boss)
check('hint: a prompt far from the end is still found', h2.user_vars.get('agent_hint') == 'buried prompt', h2.user_vars)

transcript('sid542', lp('x' * 300))
fw.poll(boss)
check('hint: a long prompt is cut', len(h2.user_vars.get('agent_hint', '')) == fw.HINT_LENGTH, h2.user_vars)

h3 = AgentWindow(43, 543)
boss.all_windows = [h3]
write_titled_session(543, 'sid543', name='context-e3')
transcript('sid543', user_line)
fw.poll(boss)
transcript('sid543', lp('yes'), lp('ok'))
fw.poll(boss)
check('hint: with only short prompts, the last of them', h3.user_vars.get('agent_hint') == 'ok', h3.user_vars)
transcript('sid543', user_line)
fw.poll(boss)
check('hint: a session with no prompt has none', 'agent_hint' not in h3.user_vars, h3.user_vars)
os.remove(os.path.join(agent_home, '.claude', 'sessions', '543.json'))
fw.poll(boss)
check('hint: closed windows are forgotten', set(fw.published_hint) <= {43}, fw.published_hint)

os.environ['HOME'] = real_home

# a changed watcher is loaded beside the old copy, which it has to silence
old = load('focus_watcher')
old.timer_started = True
kitty.launch.watcher_modules['/old/focus_watcher.py'] = dict(vars(old))
kitty.launch.watcher_modules['/new/focus_watcher.py'] = dict(vars(fw))
kitty.launch.watcher_modules['/other/watcher.py'] = {'on_focus_change': lambda *a: None}
fw.retire_older_copies()
old.published[9] = 'working'
old.poll(AgentBoss())
check('an older copy of the watcher stops polling', old.published == {9: 'working'}, old.published)
check('an older copy hands its focus events to this one', old.refresh is fw.refresh and fw.refresh.__module__ == 'focus_watcher')
check('this copy keeps polling', fw.poll.__name__ == 'poll' and vars(fw)['poll'] is fw.poll)

# tab_bar.py: one marker per tab, the most pressing of its windows' agent states
import kitty.tab_bar as ktb  # noqa: E402

tb = load('tab_bar')
# real colour codes; `tab` (back to the tab's own colour) needs a tab being drawn
real_fg = ktb.ColorFormatter('fg')
fmt = type('Fmt', (), {'bold': '<b>', 'nobold': '</b>',
                       'fg': type('Fg', (), {'red': real_fg.red, 'green': real_fg.green, 'yellow': real_fg.yellow, 'cyan': real_fg.cyan, 'tab': '<tab>'})()})()


def tab_marker(*states):
    windows = [type('W', (), {'user_vars': {'agent_state': s} if s else {}})() for s in states]
    tb.get_boss = lambda: type('Boss', (), {'tab_for_id': lambda self, tab_id: windows if tab_id == 7 else None})()
    return tb.status_line({'tab_id': 7, 'fmt': fmt})


red, green, yellow, back = '<b>' + fmt.fg.red, '<b>' + fmt.fg.green, '<b>' + fmt.fg.yellow, '</b>' + fmt.fg.tab
check('tab marker: blocked beats everything (the second line)', tab_marker('working', 'done', 'blocked', '') == f'{red}!{back}', repr(tab_marker('working', 'done', 'blocked', '')))
check('tab marker: done beats working', tab_marker('idle', 'working', 'done') == f'{green}✓{back}')
check('tab marker: working', tab_marker('idle', 'working') == f'{yellow}…{back}')
check('tab marker: an idle agent is just "claude", no agents nothing', tab_marker('idle', '') == ' claude' and tab_marker() == '')
check('tab marker: colours differ and are set', len({red, green, yellow, back}) == 4 and all((red, green, yellow, back)), (red, green, yellow, back))
tb.get_boss = lambda: None
check('tab marker: an error draws nothing', tb.draw_title({'tab_id': 7, 'fmt': fmt}) == '')
check('tab marker: an error still draws the title', tb.draw_title({'tab_id': 7, 'fmt': fmt, 'title': 'a/b'}) == 'a/b')

# tab_bar.py: the title follows the marker, a path cut down to its last directory
for title, want in (
    ('project-tools', 'project-tools'),
    ('github.com/garethrowlands/project-tools', 'g/g/project-tools'),
    ('work/project-tools', 'w/project-tools'),
    ('gitlab.com/group/subgroup/team/api', '…/s/t/api'),
    ('/Users/gareth/worktrees/project-tools/fix-tabs', '…/w/p/fix-tabs'),
    ('/tmp/scratch', '/t/scratch'),
    ('~/.config/kitty', '~/.c/kitty'),
    ('/opt/thing/', '/o/thing'),
    ('/', '/'),
    ('', ''),
    ('My Work/Client Projects/big site', 'M/C/big site'),
):
    check(f'tab title: {title!r}', tb.short_title(title) == want, repr(tb.short_title(title)))
tb.get_boss = lambda: type('Boss', (), {'tab_for_id': lambda self, tab_id: [type('W', (), {'user_vars': {'agent_state': 'blocked'}})()]})()
check('tab title: no colour for the dropped directories without the tab\'s colours', tb.draw_title({'tab_id': 7, 'fmt': fmt, 'title': '/a/b/c/d'}) == f'…/b/c/d\n{red}!{back}')
# a real formatter, mid-draw: white text on a #204060 tab
tab_fg = ktb.ColorFormatter('fg')
tab_fg.tab_data = object()
tab_fg.draw_data = type('DrawData', (), {'tab_fg': lambda self, tab: 0xffffff, 'tab_bg': lambda self, tab: 0x204060})()
real_fmt = type('Fmt', (), {'fg': tab_fg})()
tb.get_boss = lambda: None
check('tab title: the dropped directories are halfway to the background',
      tb.draw_title({'tab_id': 7, 'fmt': real_fmt, 'title': '/a/b/c/d'}) == f'{tab_fg._8f9faf}…/{tab_fg._ffffff}b/c/d',
      repr(tb.draw_title({'tab_id': 7, 'fmt': real_fmt, 'title': '/a/b/c/d'})))
check('tab title: no colour codes when nothing is dropped', tb.draw_title({'tab_id': 7, 'fmt': real_fmt, 'title': 'a/b/c'}) == 'a/b/c')
tb.get_boss = lambda: type('Boss', (), {'tab_for_id': lambda self, tab_id: [type('W', (), {'user_vars': {'agent_state': 'blocked'}})()]})()
for is_active, style, want in ((True, 'active_tab_font_style', ''), (False, 'inactive_tab_font_style', '</b>')):
    fmt.fg.tab_data = type('TabData', (), {'is_active': is_active})()
    tb.get_options = lambda: type('Opts', (), {'active_tab_font_style': (True, True), 'inactive_tab_font_style': (False, False)})()
    check(f'tab marker: bold ends after it unless the tab is bold ({style})',
          tb.draw_title({'tab_id': 7, 'fmt': fmt, 'title': 't'}) == f't\n<b>{fmt.fg.red}!{want}<tab>', repr(tb.draw_title({'tab_id': 7, 'fmt': fmt, 'title': 't'})))
del fmt.fg.tab_data
check('tab title: the marker is on the second line', tb.draw_title({'tab_id': 7, 'fmt': fmt, 'title': 'github.com/me/proj'}) == f'g/m/proj\n{red}!{back}')


# tab_bar.py: the activity symbol, for windows without an agent only
def tab_activity(symbol, *windows):
    # each window is (agent state or '', has activity)
    tab = [type('W', (), {'user_vars': {'agent_state': s} if s else {}, 'has_activity_since_last_focus': a})() for s, a in windows]
    tb.get_boss = lambda: type('Boss', (), {'tab_for_id': lambda self, tab_id: tab})()
    tb.get_options = lambda: type('Opts', (), {'tab_activity_symbol': symbol, 'active_tab_font_style': (False, False), 'inactive_tab_font_style': (False, False)})()
    return tb.draw_title({'tab_id': 7, 'fmt': fmt, 'title': 't'})


plain_red = fmt.fg.red
check('activity: a window without an agent shows the symbol', tab_activity('>', ('', True), ('', False)) == f'{plain_red}><tab>t', repr(tab_activity('>', ('', True), ('', False))))
check('activity: an agent\'s activity does not count', tab_activity('>', ('idle', True), ('working', True), ('', False)) == f't\n{yellow}…{back}')
check('activity: it stays on the first line, the marker is on the second', tab_activity('>', ('working', True), ('', True)) == f'{plain_red}><tab>t\n{yellow}…{back}')
check('activity: nothing without activity', tab_activity('>', ('', False)) == 't')
check('activity: nothing when the symbol is off', tab_activity(None, ('', True)) == 't' and tab_activity('', ('', True)) == 't')


# tab_bar.py: the second line of a vertical tab: the session title of the most pressing agent, else a running command
class TW:
    def __init__(self, state='', title='', at='0', prompt=True, cmd='', hint='', proc=''):
        self.user_vars = {'agent_state': state, 'agent_state_at': at, **({'agent_title': title} if title else {}),
                          **({'agent_hint': hint} if hint else {})} if state else {}
        self.at_prompt, self.last_cmd_cmdline = prompt, cmd
        if proc:
            self.child = type('Child', (), {'foreground_processes': [{'cmdline': [proc]}]})()


W, B = f'{yellow}…{back}', f'{red}!{back}'


def cy(text, mark=''):
    # an agent's marker, then its session title (the dim colour is '' without a real tab being drawn)
    return f'{mark}{text}'


def second_line(*windows, active=None):
    tab = list(windows)
    tab_obj = type('T', (list,), {'active_window': active})(tab)
    tb.get_boss = lambda: type('Boss', (), {'tab_for_id': lambda self, tab_id: tab_obj})()
    return tb.status_line({'tab_id': 7, 'fmt': fmt})


check('line 2: an agent\'s session title', second_line(TW('working', 'Window switcher', '5')) == cy('Window switcher', W))
check('line 2: +N for the other agents', second_line(TW('idle', 'Old one', '1'), TW('working', 'Window switcher', '5'), TW('idle', 'Another', '2')) == cy('Window switcher +2', W))
check('line 2: the most pressing agent leads', second_line(TW('working', 'W', '9'), TW('blocked', 'B', '1'), TW('done', 'D', '5')) == cy('B +2', B))
check('line 2: of equal agents, the most recently changed', second_line(TW('working', 'Old', '1'), TW('working', 'New', '9')) == cy('New +1', W))
check('line 2: an agent with no title yet has just its marker', second_line(TW('working', '', '5')) == W)
check('line 2: an idle agent with no title is just "claude"', second_line(TW('idle', '', '5')) == ' claude')
check('line 2: a command running in a window with no agent', second_line(TW(), TW(prompt=False, cmd='pnpm dev')) == ' pnpm dev')
check('line 2: the active window\'s command first', (lambda a: second_line(TW(prompt=False, cmd='tail -f log'), a, active=a))(TW(prompt=False, cmd='pnpm   dev')) == ' pnpm dev')
tb.get_options = lambda: type('Opts', (), {'tab_title_max_length': 10, 'active_tab_font_style': (False, False), 'inactive_tab_font_style': (False, False)})()
check('line 2: a long title is cut to leave room for +N', second_line(TW('working', 'abcdefghijklmnop', '5'), TW('idle', 'x', '1')) == cy('abcde… +1', W), repr(second_line(TW('working', 'abcdefghijklmnop', '5'), TW('idle', 'x', '1'))))
check('line 2: a short title is left alone', second_line(TW('working', 'abc', '5'), TW('idle', 'x', '1')) == cy('abc +1', W))
check('line 2: a lone long title is cut to the width', second_line(TW('working', 'abcdefghijklmnop', '5')) == cy('abcdefgh…', W), repr(second_line(TW('working', 'abcdefghijklmnop', '5'))))
check('line 2: a title that just fits is left alone', second_line(TW('working', 'abcdefgh', '5')) == cy('abcdefgh', W))
fmt.fg.tab_data = type('TabData', (), {'is_active': True})()
check('line 2: on the active tab it is in the tab\'s own colours', second_line(TW('working', 'Title', '5')) == W + 'Title', repr(second_line(TW('working', 'Title', '5'))))
del fmt.fg.tab_data
check('line 2: nothing at a prompt', second_line(TW(), TW(cmd='ls')) == '')
check('line 2: an agent\'s window is not a program', second_line(TW('working', 'Title', '5', prompt=False, cmd='claude')) == cy('Title', W))
check('line 2: an agent beats a program', second_line(TW(prompt=False, cmd='pnpm dev'), TW('idle', 'Title', '5')) == cy('Title', ' '))
check('line 2: no tab, no line', (setattr(tb, 'get_boss', lambda: type('Boss', (), {'tab_for_id': lambda self, i: None})()) or tb.status_line({'tab_id': 7, 'fmt': fmt})) == '')
second_line(TW('working', 'T', '5'))
drawn = tb.draw_title({'tab_id': 7, 'fmt': fmt, 'title': 'proj'})
check('line 2: draw_title puts it on a second line', drawn.endswith('proj\n' + cy('T', W)), repr(drawn))
second_line(TW())
check('line 2: a tab with nothing to say stays one line', '\n' not in tb.draw_title({'tab_id': 7, 'fmt': fmt, 'title': 'proj'}))


# tab_bar.py: with tab_title_max_lines 4, a line for each agent, then for each running command
tb.get_options = lambda: type('Opts', (), {'tab_title_max_lines': 4, 'tab_title_max_length': 20,
                                           'active_tab_font_style': (False, False), 'inactive_tab_font_style': (False, False)})()
D = f'{green}✓{back}'


def lines(*windows, active=None):
    return second_line(*windows, active=active).split('\n')


check('lines: an agent each, the most pressing first',
      lines(TW('working', 'Build', '5'), TW('blocked', 'Fix', '1'), TW('done', 'Ship', '3')) == [cy('Fix', B), cy('Ship', D), cy('Build', W)],
      lines(TW('working', 'Build', '5'), TW('blocked', 'Fix', '1'), TW('done', 'Ship', '3')))
check('lines: more than fit end with how many more',
      lines(TW('blocked', 'A', '1'), TW('done', 'B', '2'), TW('working', 'C', '3'), TW('working', 'D', '4'), TW('idle', 'E', '5'))
      == [cy('A', B), cy('B', D), ' +3 more'],
      lines(TW('blocked', 'A', '1'), TW('done', 'B', '2'), TW('working', 'C', '3'), TW('working', 'D', '4'), TW('idle', 'E', '5')))
check('lines: exactly as many as fit all show', len(lines(TW('working', 'A', '1'), TW('working', 'B', '2'), TW('working', 'C', '3'))) == 3)
check('lines: an idle agent has a blank where the marker goes', lines(TW('working', 'A', '5'), TW('idle', 'B', '1')) == [cy('A', W), cy('B', ' ')])
check('lines: the marker\'s cell is kept when nothing has a marker', lines(TW('idle', 'A', '5'), TW('idle', 'B', '1')) == [cy('A', ' '), cy('B', ' ')])
check('lines: the status icon shows without a session title', lines(TW('working', '', '5'), TW('idle', 'B', '1')) == [W, cy('B', ' ')])
check('lines: and alone', lines(TW('blocked', '', '5')) == [B])
check('lines: an idle agent with no title is "claude", lined up', lines(TW('working', 'A', '5'), TW('idle', '', '1')) == [cy('A', W), ' claude'])
check('lines: an untitled agent shows its last prompt, quoted', lines(TW('idle', '', '5', hint='which service?'), TW('idle', '', '1', hint='And ADR-0011? Tersely please')) == [cy('\u201cwhich service?', ' '), cy('\u201cAnd ADR-0011? Ter…', ' ')])
check('lines: a marked untitled agent shows the marker, then the prompt', lines(TW('working', '', '5', hint='fix it'), TW('idle', 'Named', '1')) == [cy('\u201cfix it', W), cy('Named', ' ')])
check('lines: a title beats the hint', lines(TW('idle', 'Named', '5', hint='fix it')) == [cy('Named', ' ')])
check('lines: two untitled idle agents', lines(TW('idle', '', '5'), TW('idle', '', '1')) == [' claude', ' claude'])
check('lines: commands follow the agents', lines(TW(prompt=False, cmd='pnpm dev'), TW('working', 'A', '5')) == [cy('A', W), ' pnpm dev'])
check('lines: commands alone have the gutter too', lines(TW(prompt=False, cmd='pnpm dev'), TW(prompt=False, cmd='tail -f log')) == [' pnpm dev', ' tail -f log'])
check('lines: commands past the last line are counted too',
      lines(TW('working', 'A', '5'), TW(prompt=False, cmd='a'), TW(prompt=False, cmd='b'), TW(prompt=False, cmd='c')) == [cy('A', W), ' a', ' +2 more'])
check('lines: a shell at a prompt shows its name', lines(TW(proc='-zsh')) == [' zsh'])
check('lines: a path to the shell is cut to its name', lines(TW(proc='/bin/fish')) == [' fish'])
check('lines: a running command beats the process name', lines(TW(prompt=False, cmd='pnpm dev', proc='node')) == [' pnpm dev'])
check('lines: with no command reported, the running process', lines(TW(prompt=False, proc='sleep')) == [' sleep'])
check('lines: commands, then shells at a prompt', lines(TW(proc='zsh'), TW(prompt=False, cmd='pnpm dev', proc='zsh')) == [' pnpm dev', ' zsh'])
check('lines: agents, then shells', lines(TW('working', 'A', '5'), TW(proc='zsh')) == [cy('A', W), ' zsh'])
check('lines: a window with no process to name says nothing', lines(TW(), TW(proc='zsh'))[0] == ' zsh' and len(lines(TW(), TW(proc='zsh'))) == 1)
check('lines: nothing to say is no lines', second_line(TW(), TW(cmd='ls')) == '')
check('lines: a long title is cut to the width less the marker', lines(TW('working', 'abcdefghijklmnopqrstuvwxyz', '5')) == [cy('abcdefghijklmnopqr…', W)],
      lines(TW('working', 'abcdefghijklmnopqrstuvwxyz', '5')))
check('lines: and its padded neighbour likewise', lines(TW('working', 'A', '5'), TW('idle', 'abcdefghijklmnopqrstuvwxyz', '1'))[1] == cy('abcdefghijklmnopqr…', ' '))

# a window's program line is redrawn when its command starts or ends
pw = AgentWindow(31, 599, proc='zsh')
pw.program_status = Status()
pw.at_prompt, pw.last_cmd_cmdline = True, ''
pboss = AgentBoss(pw)
fw.poll(pboss)
pdirty = pboss.dirty
fw.poll(pboss)
check('program: nothing redrawn while it stays', pboss.dirty == pdirty, (pboss.dirty, pdirty))
pw.at_prompt, pw.last_cmd_cmdline = False, 'sleep 5'
fw.poll(pboss)
check('program: a command starting redraws the tab bar', pboss.dirty == pdirty + 1, (pboss.dirty, pdirty))
fw.poll(pboss)
check('program: and only once', pboss.dirty == pdirty + 1, (pboss.dirty, pdirty))
pw.at_prompt = True
fw.poll(pboss)
check('program: a command ending redraws it too', pboss.dirty == pdirty + 2, (pboss.dirty, pdirty))

print(f'\n{failures} failure(s)' if failures else '\nALL OK')
sys.exit(1 if failures else 0)
