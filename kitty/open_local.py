"""Open clicked local file links in a TUI instead of a GUI app.

Invoked from open-actions.conf as:
    kitten open_local.py ${FILE_PATH} ${URL}
and from kitty.conf, in a glow overlay, as:
    kitten open_local.py --obsidian

What a click does:
  directory      cd in the pane's zsh if it is idle at a prompt (see
                 kitty-cd-link.zsh); otherwise yazi in an overlay
  file#LINE      micro at that line (rg --hyperlink-format=kitty links)
  Markdown       glow TUI (e edits in $EDITOR, o opens in Obsidian if the
                 note is inside a vault)
  other text     micro
  anything else  yazi with the file selected
Overlays cover the clicked pane, start in its directory and copy its
environment (EDITOR, PAGER, PATH).
"""

import codecs
import json
import os
from typing import Any
from urllib.parse import quote, unquote, urlparse

from kittens.tui.handler import result_handler
from kitty.utils import log_error

TRIGGER = '\x1b[29271~'
TERMINATOR = '\a'
SHELL_PID_VAR = 'kitty_cd_link_pid'
MD_PATH_VAR = 'kitty_md_path'
EDITOR_VAR = 'kitty_editor'
MARKDOWN_EXTS = ('.md', '.markdown')
OBSIDIAN_REGISTRY = os.path.expanduser('~/Library/Application Support/obsidian/obsidian.json')


def main(args: list[str]) -> None:
    pass


def resolve(path: str, url: str) -> tuple[str, int]:
    # eza does not percent-encode '#', '?' or '%' in names, so kitty may have
    # split the path at '#'/'?' or decoded a literal '%xx'. Prefer the whole
    # raw path if it exists; otherwise a numeric fragment is a line number.
    raw = ''
    if url.startswith('file://'):
        raw = url[len('file://'):]
        raw = raw[raw.find('/'):] if '/' in raw else ''
    whole = unquote(raw, errors='surrogateescape')
    if whole.startswith('/') and os.path.exists(whole):
        return whole, 0
    if path.startswith('/') and os.path.exists(path):
        frag = unquote(urlparse(url).fragment)
        return path, int(frag) if frag.isdigit() else 0
    if raw.startswith('/') and os.path.exists(raw):
        return raw, 0
    return '', 0


def is_text(path: str) -> bool:
    try:
        with open(path, 'rb') as f:
            chunk = f.read(8192)
    except OSError:
        return False
    if b'\0' in chunk:
        return False
    try:
        codecs.getincrementaldecoder('utf-8')().decode(chunk, final=False)
    except UnicodeDecodeError:
        return False
    return True


def shell_refusal(window: Any) -> str:
    if window.child_is_remote:
        return 'remote session'
    if not window.screen.is_main_linebuf():
        return 'full-screen program running'
    if not window.at_prompt:
        return 'not at a shell prompt'
    try:
        shell_pid = int(window.user_vars.get(SHELL_PID_VAR, ''))
    except ValueError:
        return 'zsh link handler not loaded in this pane'
    if shell_pid not in {p['pid'] for p in window.child.foreground_processes}:
        return 'foreground process is not the announcing zsh'
    return ''


def overlay(boss: Any, window: Any, cmd: list[str], user_vars: tuple[str, ...] = ()) -> None:
    from kitty.launch import launch, parse_launch_args

    largs = ['--type=overlay', '--cwd=current', '--copy-env']
    if window is not None:
        largs += [f'--source-window=id:{window.id}', f'--next-to=id:{window.id}']
        # --copy-env only sees the shell's exec-time environment; the shell
        # publishes its current $EDITOR as a user var (kitty-cd-link.zsh).
        if editor := window.user_vars.get(EDITOR_VAR, ''):
            largs += ['--env', f'EDITOR={editor}', '--env', f'VISUAL={editor}']
    for v in user_vars:
        largs += ['--var', v]
    opts, cmd = parse_launch_args(largs + ['--', *cmd])
    launch(boss, opts, cmd)


def obsidian_vaults() -> list[str]:
    try:
        with open(OBSIDIAN_REGISTRY) as f:
            vaults = json.load(f).get('vaults', {}).values()
        return [os.path.realpath(v['path']) for v in vaults if v.get('path')]
    except Exception:
        return []


def in_vault(path: str) -> bool:
    real = os.path.realpath(path)
    return any(os.path.commonpath([real, v]) == v for v in obsidian_vaults())


def open_in_obsidian(boss: Any, window: Any) -> None:
    from kitty.utils import open_url

    path = window.user_vars.get(MD_PATH_VAR, '') if window is not None else ''
    if not path:
        return
    if not in_vault(path):
        boss.show_error('Not in an Obsidian vault', path)
        return
    open_url('obsidian://open?path=' + quote(os.path.realpath(path), safe=''))


@result_handler(no_ui=True)
def handle_result(args: list[str], answer: Any, target_window_id: int, boss: Any) -> None:
    window = boss.window_id_map.get(target_window_id)
    if args[1:2] == ['--obsidian']:
        open_in_obsidian(boss, window)
        return
    path = args[1] if len(args) > 1 else ''
    url = args[2] if len(args) > 2 else 'file://' + path
    path, line = resolve(path, url)
    if not path:
        log_error(f'open_local: no such local file: {url!r}')
        return
    if os.path.isdir(path):
        if window is not None and not shell_refusal(window):
            window.write_to_child(TRIGGER + path.encode('utf-8', 'surrogateescape').hex() + TERMINATOR)
        else:
            overlay(boss, window, ['yazi', path])
    elif line:
        overlay(boss, window, ['micro', path, f'+{line}'])
    elif path.lower().endswith(MARKDOWN_EXTS):
        overlay(boss, window, ['glow', '--tui', path], (f'{MD_PATH_VAR}={path}',))
    elif is_text(path):
        overlay(boss, window, ['micro', path])
    else:
        overlay(boss, window, ['yazi', path])
