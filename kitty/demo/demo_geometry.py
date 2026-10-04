"""Write the pixel geometry of every kitty window as JSON, for kitty/demo's
mouse targets (geometry.zsh turns it into screen points).

    kitten @ kitten /path/to/kitty/demo/demo_geometry.py OUTFILE

`kitten @ ls` has no pixel positions, so this reads them inside kitty:
Window.geometry (the pane's cell area, framebuffer pixels) and
get_os_window_size(). Both are kitty internals rather than a documented API;
play's pre-flight never needs them, but the first mouse verb of a run does,
so a kitty upgrade that changes them fails a rehearsal, not a take.
The file is written atomically, so a reader polling for it never sees half.
"""

import json
import os
from collections.abc import Callable, Iterable
from typing import Any

from kittens.tui.handler import result_handler

SIZE_KEYS = ('width', 'height', 'framebuffer_width', 'framebuffer_height')


def main(args: list[str]) -> None:
    pass


def payload(windows: Iterable[Any], os_window_size: Callable[[int], Any]) -> dict[str, Any]:
    out: dict[str, Any] = {'os_windows': {}, 'windows': {}}
    for w in windows:
        g = w.geometry
        out['windows'][str(w.id)] = {
            'os_window_id': w.os_window_id,
            'left': g.left, 'top': g.top, 'right': g.right, 'bottom': g.bottom,
            'columns': w.screen.columns, 'lines': w.screen.lines,
        }
        key = str(w.os_window_id)
        if key not in out['os_windows']:
            size = os_window_size(w.os_window_id) or {}
            out['os_windows'][key] = {k: size.get(k) for k in SIZE_KEYS}
    return out


def write_atomically(path: str, data: Any) -> None:
    tmp = f'{path}.tmp'
    with open(tmp, 'w') as f:
        json.dump(data, f)
    os.replace(tmp, path)


@result_handler(no_ui=True)
def handle_result(args: list[str], answer: Any, target_window_id: int, boss: Any) -> None:
    from kitty.fast_data_types import get_os_window_size
    write_atomically(args[1], payload(boss.window_id_map.values(), get_os_window_size))
