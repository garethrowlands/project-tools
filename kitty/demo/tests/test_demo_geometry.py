"""Tests for kitty/demo/demo_geometry.py.

Run with kitty's bundled Python (the kitten imports kittens.tui.handler):

    kitty +launch kitty/demo/tests/test_demo_geometry.py

kitty's windows are replaced with small fakes. Exits 1 if any test fails.
"""

import importlib.util
import json
import os
import sys
import tempfile
from types import SimpleNamespace as NS

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('demo_geometry', os.path.join(os.path.dirname(HERE), 'demo_geometry.py'))
assert spec and spec.loader
dg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dg)
failures = 0


def check(name: str, cond: object, detail: object = '') -> None:
    global failures
    print(('PASS ' if cond else 'FAIL ') + name + ('' if cond else f': {detail!r}'))
    if not cond:
        failures += 1


def win(id: int, os_id: int, left: int, top: int, right: int, bottom: int, cols: int, lines: int) -> NS:
    return NS(id=id, os_window_id=os_id, geometry=NS(left=left, top=top, right=right, bottom=bottom),
              screen=NS(columns=cols, lines=lines))


sizes = {1: {'width': 1600, 'height': 1000, 'framebuffer_width': 3200, 'framebuffer_height': 2000, 'xscale': 2.0},
         2: None}
calls: list[int] = []


def size(os_id: int) -> object:
    calls.append(os_id)
    return sizes[os_id]


out = dg.payload([win(5, 1, 0, 0, 1600, 2000, 40, 50), win(6, 1, 1600, 0, 3200, 2000, 40, 50),
                  win(9, 2, 0, 0, 10, 10, 1, 1)], size)
check('window entry', out['windows']['5'] == {'os_window_id': 1, 'left': 0, 'top': 0, 'right': 1600,
                                              'bottom': 2000, 'columns': 40, 'lines': 50}, out['windows']['5'])
check('os window keeps only the size keys', out['os_windows']['1'] == {
    'width': 1600, 'height': 1000, 'framebuffer_width': 3200, 'framebuffer_height': 2000}, out['os_windows']['1'])
check('size looked up once per os window', calls == [1, 2], calls)
check('unknown os window size gives nulls', out['os_windows']['2'] == dict.fromkeys(dg.SIZE_KEYS), out['os_windows']['2'])

with tempfile.TemporaryDirectory() as d:
    p = os.path.join(d, 'geometry.json')
    dg.write_atomically(p, out)
    with open(p) as f:
        check('written json round-trips', json.load(f) == out)
    check('no temp file left behind', os.listdir(d) == ['geometry.json'], os.listdir(d))

sys.exit(1 if failures else 0)
