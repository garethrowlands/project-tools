"""Global kitty watcher: stamps each window with when you last looked at it.

Enable in kitty.conf (applies to windows created after the config loads):

    watcher focus_watcher.py

Sets the window's `seen_at` user var (wall-clock epoch seconds) both when it
gains focus and when it loses it, so `kitty @ ls` shows it under `user_vars`.
kitty's own `last_focused_at` only records the gain, which can't tell "the
agent finished while I was watching" from "it finished after I left" —
zsh/functions/claude-session.zsh compares `seen_at` with the Claude session's
last status change to decide whether a finished agent is still unseen.
"""

import time
from typing import Any


def on_focus_change(boss: Any, window: Any, data: dict[str, Any]) -> None:
    window.set_user_var('seen_at', str(int(time.time())))
