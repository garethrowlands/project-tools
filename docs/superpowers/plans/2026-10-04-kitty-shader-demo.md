# kitty Shader Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A self-running, screen-recordable show-off of the kitty custom shaders: `kitty/demo/play` turns the pane it runs in into a presenterm deck, then a background director builds and tears down stage panes, tabs and a second OS window, and drives keys and the real mouse pointer (via Hammerspoon) so every effect happens live.

**Architecture:** `play` (zsh) runs pre-flight checks, starts the director as a disowned background subshell, and `exec`s presenterm in the same pane. The director sources one file per beat from `beats/`; beats are written only in verbs from `lib.zsh`, which wrap `kitten @` (kitty remote control) and `hs -c` (Hammerspoon CLI, module `stage.lua`). Pixel geometry for mouse targets comes from a small in-kitty kitten (`demo_geometry.py`) and is converted to screen points by pure jq functions in `geometry.zsh`. Self-describing panes run `card`.

**Tech Stack:** zsh, jq, kitty 0.49.1 remote control + a Python kitten, presenterm 0.16.1, Hammerspoon (Lua) with `hs.ipc`, micro, eza, rg.

**Spec:** `docs/superpowers/specs/2026-10-04-kitty-shader-demo-design.md`

## Global Constraints

- kitty ≥ 0.49 with `custom_shaders gentle`; remote control via the existing `allow_remote_control socket-only` + `listen_on`.
- No new dependencies except enabling Hammerspoon's `hs` CLI (`hs.ipc`). Uses presenterm, micro, eza, rg, jq (all installed).
- zsh glue; Python only for the in-kitty geometry kitten. zsh tests follow the repo style: `ok`/`bad`, `exit $fail` (see `kitty/tests/kitty-cd-link-tests.zsh`). Kitten tests run with `kitty +launch` (see `kitty/tests/test_kittens.py`).
- All files live under `kitty/demo/`.
- Main kitty window is centred at **1600×1000 points** for a run and restored afterwards.
- Abort hotkey: **Ctrl+Alt+Cmd+.** (Hammerspoon).
- State dir: `$TMPDIR/kitty-demo/` (`play.pid`, `play.log`, `card-NAME.msg`, `card-NAME.pid`, `geometry.json`).
- Every readiness poll times out after **5 s** into a beat failure; `beat-pause` is for pacing only.
- The demo only ever closes kitty windows whose ids it recorded when it created them.
- Claude's sandbox cannot reach the kitty socket or Hammerspoon. Steps marked **(manual)** are run by the user in kitty; everything else (all automated tests) runs anywhere.

## Review Focus

1. **The viewer quits presenterm mid-run** (q in the deck): the director must stop at the next verb and clean up, leaving nothing behind. — Task 3 test "verbs stop when the deck has gone"; Task 6 traps HUP.
2. **`--from N` / `--only N` without the panes earlier beats would have left**: beats must still run. — Task 3 test "pane close of an unknown name is a no-op"; Task 8 test "`--only 7` opens C itself".
3. **A second `play` while one is running**: refused with a reason, nothing touched. — Task 6 tests for `demo_already_running`.
4. **A demo pane was closed by hand before cleanup**: cleanup must still close the rest and restore layout and frame. — Task 3 test "cleanup survives a window that has already gone".
5. **A mouse target that isn't on screen** (text scrolled away, unknown window): the beat fails with a clear message and the pointer does not move. — Task 5 tests for `mouse glide-text` / `mouse glide`.

---

## File Structure

```
kitty/demo/
  play                 entry point + director (zsh, executable)
  lib.zsh              verbs + run state + cleanup (sourced)
  geometry.zsh         pure: geometry JSON + frame -> screen points; find text on screen
  demo_geometry.py     kitten: writes every window's pixel geometry as JSON
  card                 self-describing pane program (zsh, executable)
  stage.lua            Hammerspoon module `demoStage`
  deck.md              presenterm slides (11)
  beats/00-intro.zsh … beats/10-finale.zsh
  scene/comet.txt      self-narrating file for the cursor beat
  scene/repo/          main.py, README.md, glitter/sparkle.txt for the link beat
  tests/demo-tests.zsh
  tests/test_demo_geometry.py
  README.md
```

Modified: `CLAUDE.md` (tests + architecture), `.claude/skills/install-scripts/SKILL.md` (Hammerspoon setup), `~/.hammerspoon/init.lua` (manual, outside the repo).

---

### Task 1: Geometry functions and the test suite skeleton

**Files:**
- Create: `kitty/demo/geometry.zsh`
- Create: `kitty/demo/tests/demo-tests.zsh`
- Modify: `CLAUDE.md` (Running Tests block)

**Interfaces:**
- Produces:
  - `demo_point_in_pane GEOM FRAME ID XPCT YPCT` → prints `"X Y"` (integer screen points); status 1 and no output if ID/its OS window is missing or input is bad.
  - `demo_point_at_cell GEOM FRAME ID ROW COL` → prints `"X Y"` of the centre of that cell (0-based); same failure contract.
  - `demo_find_text TEXT LITERAL` → prints `"ROW COL"` (0-based) of LITERAL's first occurrence; status 1 if absent.
  - GEOM JSON shape (written by Task 2's kitten): `{"os_windows":{"<os id>":{"width","height","framebuffer_width","framebuffer_height"}},"windows":{"<win id>":{"os_window_id","left","top","right","bottom","columns","lines"}}}` — framebuffer pixels.
  - FRAME JSON (from Task 5's `demoStage.frame()`): `{"x","y","w","h"}` in screen points, title bar included; content area = bottom `height` points.
  - Test helpers in `demo-tests.zsh`: `ok NAME`, `bad NAME`, `is NAME ACTUAL EXPECTED`, `$T` (temp dir), `$DEMO_ROOT`.

- [ ] **Step 1: Write the failing tests**

`kitty/demo/tests/demo-tests.zsh`:

```zsh
#!/usr/bin/env zsh
# Tests for kitty/demo: geometry, the verbs (kitty and Hammerspoon stubbed),
# card and play. Needs neither kitty nor Hammerspoon.
#
#   zsh kitty/demo/tests/demo-tests.zsh
#
# Exits 1 if any test fails.

DEMO_ROOT=${0:A:h:h}
T=$(mktemp -d)
trap 'rm -rf $T' EXIT
fail=0

ok()  { print -r "PASS $1" }
bad() { print -r "FAIL $1"; fail=1 }
is()  { [[ $2 == "$3" ]] && ok $1 || bad "$1: got ${(q+)2}, want ${(q+)3}" }

source $DEMO_ROOT/geometry.zsh

# --- geometry ---------------------------------------------------------------
# Retina: 2 framebuffer pixels per point. Window 5 fills the left half, 6 the
# right half (40 columns x 50 lines of 40x40 px cells). The frame's title bar
# is 28 points (1028 - 1000).
GEOM='{"os_windows":{"1":{"width":1600,"height":1000,"framebuffer_width":3200,"framebuffer_height":2000}},
       "windows":{"5":{"os_window_id":1,"left":0,"top":0,"right":1600,"bottom":2000,"columns":40,"lines":50},
                  "6":{"os_window_id":1,"left":1600,"top":0,"right":3200,"bottom":2000,"columns":40,"lines":50}}}'
FRAME='{"x":100,"y":50,"w":1600,"h":1028}'

is 'pane centre in points'       "$(demo_point_in_pane $GEOM $FRAME 5 50 50)" '500 578'
is 'pane corner in points'       "$(demo_point_in_pane $GEOM $FRAME 6 0 0)"   '900 78'
is 'cell centre in points'       "$(demo_point_at_cell $GEOM $FRAME 6 2 3)"   '970 128'
demo_point_in_pane $GEOM $FRAME 99 50 50 >/dev/null && bad 'unknown window accepted' || ok 'unknown window rejected'
demo_point_at_cell $GEOM $FRAME 5 x 1 >/dev/null && bad 'bad row accepted' || ok 'bad row rejected'

is 'find text'                   "$(demo_find_text $'ab\nxx TODO: hi\n' 'TODO: hi')" '1 3'
is 'find text after empty rows'  "$(demo_find_text $'\n\nxx a*b' 'a*b')" '2 3'
is 'find text at row start'      "$(demo_find_text $'glitter\nmain.py' 'main.py')" '1 0'
demo_find_text $'a*c\nabc' 'a*b' >/dev/null && bad 'glob chars matched as a pattern' || ok 'glob chars are literal'
demo_find_text $'abc' 'zzz' >/dev/null && bad 'absent text found' || ok 'absent text not found'

# (later tasks add sections above this line)
exit $fail
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh kitty/demo/tests/demo-tests.zsh`
Expected: error `no such file or directory: .../kitty/demo/geometry.zsh`, then FAIL lines; exit 1.

- [ ] **Step 3: Implement `kitty/demo/geometry.zsh`**

```zsh
# Pure geometry for kitty/demo: turn a target inside a kitty pane into a
# screen point for Hammerspoon. No kitty or Hammerspoon calls, so it is unit
# tested with fixture JSON (tests/demo-tests.zsh).
#
# GEOM is the JSON demo_geometry.py writes, in framebuffer pixels:
#   {"os_windows": {"1": {"width": 1600, "height": 1000,
#                         "framebuffer_width": 3200, "framebuffer_height": 2000}},
#    "windows": {"5": {"os_window_id": 1, "left": 0, "top": 0, "right": 1600,
#                      "bottom": 2000, "columns": 40, "lines": 50}}}
# left/top/right/bottom bound the pane's cell area (padding excluded).
# FRAME is the OS window's frame in screen points from demoStage.frame(),
# title bar included: {"x": 100, "y": 50, "w": 1600, "h": 1028}. The content
# area is the bottom `height` points of it.

_demo_geom_jq='
  (.windows[$id] // error("no window")) as $w
  | (.os_windows[$w.os_window_id | tostring] // error("no os window")) as $o
  | ($o.width / $o.framebuffer_width) as $sx
  | ($o.height / $o.framebuffer_height) as $sy
  | def screen($px; $py):
      "\(($f.x + $px * $sx) | round) \(($f.y + $f.h - $o.height + $py * $sy) | round)";
'

# demo_point_in_pane GEOM FRAME ID XPCT YPCT -> "x y", XPCT/YPCT 0..100 of the pane.
demo_point_in_pane() {
  jq -r --arg id "$3" --argjson f "$2" --argjson xp "$4" --argjson yp "$5" "$_demo_geom_jq"'
    screen($w.left + ($w.right - $w.left) * $xp / 100;
           $w.top + ($w.bottom - $w.top) * $yp / 100)' <<<"$1" 2>/dev/null
}

# demo_point_at_cell GEOM FRAME ID ROW COL -> "x y", the centre of that cell
# (0-based row and column of the visible screen).
demo_point_at_cell() {
  jq -r --arg id "$3" --argjson f "$2" --argjson row "$4" --argjson col "$5" "$_demo_geom_jq"'
    screen($w.left + ($col + 0.5) * ($w.right - $w.left) / $w.columns;
           $w.top + ($row + 0.5) * ($w.bottom - $w.top) / $w.lines)' <<<"$1" 2>/dev/null
}

# demo_find_text TEXT LITERAL -> "row col" (0-based) of LITERAL's first
# occurrence in TEXT, one screen row per line; status 1 if it isn't there.
# Columns count characters, so wide characters (emoji, CJK) earlier on the
# row would put it off; the demo's scenes avoid them.
demo_find_text() {
  local -a rows=("${(@f)1}")
  local i prefix
  for (( i = 1; i <= $#rows; i++ )); do
    prefix=${rows[i]%%"$2"*}
    if [[ $prefix != "$rows[i]" ]]; then
      print -r -- "$(( i - 1 )) ${#prefix}"
      return 0
    fi
  done
  return 1
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh kitty/demo/tests/demo-tests.zsh`
Expected: 10 `PASS` lines, no `FAIL`; exit 0.

- [ ] **Step 5: Add the suite to CLAUDE.md**

In `CLAUDE.md`, inside the "Running Tests" zsh block, after the `sw-tests.zsh` line add:

```
zsh kitty/demo/tests/demo-tests.zsh
kitty +launch kitty/demo/tests/test_demo_geometry.py
```

and append to the paragraph below the block: `` `kitty/demo`'s suites test the shader demo's geometry, verbs (kitty and Hammerspoon stubbed), card and play; see `kitty/demo/README.md`. ``

- [ ] **Step 6: Commit**

```bash
git add kitty/demo/geometry.zsh kitty/demo/tests/demo-tests.zsh CLAUDE.md
git commit -m "kitty demo: geometry for mouse targets

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The geometry kitten

**Files:**
- Create: `kitty/demo/demo_geometry.py`
- Test: `kitty/demo/tests/test_demo_geometry.py`

**Interfaces:**
- Consumes: the GEOM JSON shape from Task 1.
- Produces:
  - `kitten @ kitten /abs/path/kitty/demo/demo_geometry.py OUTFILE` writes GEOM JSON to OUTFILE atomically (via `OUTFILE.tmp` + rename).
  - Python: `payload(windows, os_window_size) -> dict`, `write_atomically(path, data) -> None`, `SIZE_KEYS`.

- [ ] **Step 1: Write the failing test**

`kitty/demo/tests/test_demo_geometry.py`:

```python
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `kitty +launch kitty/demo/tests/test_demo_geometry.py`
Expected: `FileNotFoundError` for `demo_geometry.py`.

- [ ] **Step 3: Implement `kitty/demo/demo_geometry.py`**

```python
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
```

- [ ] **Step 4: Run it to verify it passes**

Run: `kitty +launch kitty/demo/tests/test_demo_geometry.py`
Expected: 6 `PASS`, exit 0.

- [ ] **Step 5 (manual): Check it against the real kitty**

In a kitty pane with a split open, run:
```bash
kitten @ kitten $PWD/kitty/demo/demo_geometry.py $TMPDIR/g.json && sleep 0.5 && jq . $TMPDIR/g.json
```
Expected: every window id with plausible pixels; each OS window with non-null `width`, `height`, `framebuffer_width`, `framebuffer_height` (framebuffer ≈ 2× points on Retina). If the OS-window sizes are null, `get_os_window_size` changed in this kitty: stop and report.

- [ ] **Step 6: Commit**

```bash
git add kitty/demo/demo_geometry.py kitty/demo/tests/test_demo_geometry.py
git commit -m "kitty demo: kitten that reports window pixel geometry

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Core verbs, run state and cleanup (`lib.zsh`)

**Files:**
- Create: `kitty/demo/lib.zsh`
- Test: `kitty/demo/tests/demo-tests.zsh` (new section)

**Interfaces:**
- Consumes: `geometry.zsh` (Task 1).
- Produces (all used by beats and `play`):
  - Globals: `DEMO_ROOT`, `DEMO_IDS` (assoc name→window id, `deck` included), `DEMO_CREATED` (array of ids, oldest first), `DEMO_DRY` (0/1), `DEMO_SLOW` (number), `DEMO_BEAT`, `DEMO_STATE`, `DEMO_TIMEOUT` (s), `DEMO_LAYOUT`.
  - Replaceable outside-world functions: `demo_kitten ARGS…` (= `kitten @ ARGS…`), `demo_hs LUA` (= `hs -c LUA`), `demo_sleep SECS`.
  - Helpers: `demo_err MSG…` (prints `beat N · MSG` to stderr, returns 1), `demo_dry VERB ARGS…` (in dry run prints the `(q+)`-quoted command on one line and returns 0; else returns 1), `demo_id NAME`, `demo_poll WHAT CMD…`, `demo_lua_str STRING`, `demo_begin PIDFILE`, `demo_cleanup`.
  - Verbs: `pane open|ensure NAME [LAUNCH-OPTION…] -- CMD…`, `pane close NAME`, `focus NAME`, `keys NAME KEY…`, `type-text NAME TEXT`, `wait-text NAME TEXT`, `wait-window MATCH`, `slide goto N TEXT`, `beat-pause SECS`. NAME `focused` is accepted by `keys` and `type-text`.

- [ ] **Step 1: Write the failing tests**

Insert into `kitty/demo/tests/demo-tests.zsh` above `# (later tasks add sections above this line)`:

```zsh
# --- verbs (kitty and Hammerspoon stubbed) -----------------------------------
DEMO_STATE=$T/state
source $DEMO_ROOT/lib.zsh

# Stubs. Verbs call these inside $(...), so they keep their state in files.
# kcalls: one line per kitten call; dead: window ids kitty no longer has.
print 100 >| $T/knext; : >| $T/kcalls $T/hcalls $T/dead
demo_kitten() {
  print -r -- "$*" >> $T/kcalls
  case $1 in
    launch)
      local n=$(( $(<$T/knext) + 1 )); print $n >| $T/knext
      [[ ${@[-2]} == */card ]] && { mkdir -p $DEMO_STATE; print 1 >| $DEMO_STATE/card-${@[-1]}.pid }
      print $n ;;
    ls)           [[ $2 == --match ]] && grep -qx "${3#id:}" $T/dead && return 1
                  print -r -- ${KLSJSON:-'[]'} ;;
    close-window) ! grep -qx "${3#id:}" $T/dead ;;
    get-text)     print -r -- "$KSCREEN" ;;
    kitten)       [[ -n $KGEOM ]] && print -r -- $KGEOM >| $3 ;;
    *)            return 0 ;;
  esac
}
demo_hs() {
  print -r -- "$1" >> $T/hcalls
  case $1 in
    *demoStage.frame*) print -r -- ${HSFRAME:-'{}'} ;;
    *)                 print -r -- ${HSREPLY:-ok} ;;
  esac
}
demo_sleep() { : }
reset_stubs() {
  print 100 >| $T/knext; : >| $T/kcalls $T/hcalls $T/dead
  DEMO_IDS=(deck 7); DEMO_CREATED=(); DEMO_DRY=0; DEMO_TIMEOUT=0.2; KSCREEN=''; KLSJSON=''
}

reset_stubs
pane open A --location=vsplit -- card A hello
is 'pane open remembers the id'     "$DEMO_IDS[A] $DEMO_CREATED" '101 101'
is 'pane open launches without focus' "$(grep '^launch' $T/kcalls)" 'launch --keep-focus --title demo A --location=vsplit -- card A hello'
pane ensure A --location=vsplit -- card A hello
is 'pane ensure leaves an open pane alone' "$(grep -c '^launch' $T/kcalls)" 1
pane open B 2>$T/err && bad 'pane open without a command accepted' || ok 'pane open needs a command'
pane close A
is 'pane close forgets it'          "${DEMO_IDS[A]-gone} ${#DEMO_CREATED}" 'gone 0'
is 'pane close closes that window'  "$(grep '^close-window' $T/kcalls)" 'close-window --match id:101'
pane close nosuch && ok 'pane close of an unknown name is a no-op' || bad 'pane close of an unknown name failed'

reset_stubs
print 7 >> $T/dead
pane open A -- card A hi 2>$T/err && bad 'verbs ran without the deck' || ok 'verbs stop when the deck has gone'
[[ $(<$T/err) == *'deck pane has gone'* ]] && ok 'deck-gone message' || bad "deck-gone message: $(<$T/err)"
grep -q '^launch' $T/kcalls && bad 'launched without the deck' || ok 'nothing launched without the deck'

reset_stubs
focus nosuch 2>$T/err && bad 'focus of an unknown pane accepted' || ok 'focus of an unknown pane fails'
DEMO_BEAT=3
focus nosuch 2>$T/err
is 'errors name the beat' "$(<$T/err)" 'beat 3 · no pane named nosuch'
DEMO_BEAT=

reset_stubs
KSCREEN=$'line one\nFocus follows you'
slide goto 2 'Focus follows you' && ok 'slide goto waits for its text' || bad 'slide goto failed'
is 'slide goto types N then G'      "$(grep '^send-text' $T/kcalls)" 'send-text --match id:7 -- 2G'
wait-text deck 'not there' 2>$T/err && bad 'wait-text found absent text' || ok 'wait-text times out'
[[ $(<$T/err) == *"timed out after 0.2s waiting for 'not there' in pane deck"* ]] && ok 'timeout message' || bad "timeout message: $(<$T/err)"
keys focused ctrl+q
is 'keys can target the focused window' "$(grep '^send-key' $T/kcalls)" 'send-key --match state:focused ctrl+q'

reset_stubs
DEMO_DRY=1
is 'dry run prints the verb'        "$(pane open A --location=vsplit -- card A 'two words')" "pane open A --location=vsplit -- card A 'two words'"
out=$(slide goto 2 $'two\nlines')
is 'dry run keeps a multi-line argument on one line' "${#${(f)out}}" 1
is 'dry run calls nothing'          "$(<$T/kcalls)" ''

reset_stubs
KLSJSON='[{"tabs":[{"layout":"tall","windows":[{"id":7}]}]}]'
demo_begin $T/play.pid && ok 'demo_begin succeeds' || bad 'demo_begin failed'
is 'demo_begin remembers the layout' "$DEMO_LAYOUT" 'tall'
grep -qx 'goto-layout --match window_id:7 splits' $T/kcalls && ok 'demo_begin switches to splits' || bad 'no splits layout'
is 'demo_begin pins the window'     "$(<$T/hcalls)" "return demoStage.begin(\"$T/play.pid\", 1600, 1000)"
HSREPLY='no focused window' demo_begin $T/play.pid 2>/dev/null && bad 'demo_begin ignored Hammerspoon' || ok 'demo_begin needs Hammerspoon'

reset_stubs
DEMO_LAYOUT=tall
pane open A -- card A a; pane open B -- card B b; pane open C -- card C c
print 102 >> $T/dead
: >| $T/kcalls
demo_cleanup && ok 'cleanup succeeds' || bad 'cleanup failed'
is 'cleanup survives a window that has already gone' "$(grep '^close-window' $T/kcalls | awk '{print $3}' | paste -sd' ' -)" 'id:103 id:102 id:101'
is 'cleanup restores the layout'    "$(grep '^goto-layout' $T/kcalls)" 'goto-layout --match window_id:7 tall'
is 'cleanup forgets everything but the deck' "${(kv)DEMO_IDS} ${#DEMO_CREATED}" 'deck 7 0'
grep -q 'demoStage.finish' $T/hcalls && ok 'cleanup restores the frame' || bad 'cleanup did not call finish'
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh kitty/demo/tests/demo-tests.zsh`
Expected: `no such file or directory: .../lib.zsh` and many FAIL lines; exit 1.

- [ ] **Step 3: Implement `kitty/demo/lib.zsh`**

```zsh
# Verbs the kitty demo's beats are written in (see README.md), plus the run's
# state and cleanup. Sourced by play and by tests/demo-tests.zsh.
#
# A verb that can't do its job prints "beat N · <what>" on stderr and returns
# non-zero; play sources each beat with ERR_RETURN, so the first failure ends
# the run and play's EXIT trap calls demo_cleanup.
# With DEMO_DRY=1 every verb prints itself instead (play --dry-run).

typeset -g DEMO_ROOT=${DEMO_ROOT:-${${(%):-%x}:A:h}}
source $DEMO_ROOT/geometry.zsh

typeset -gA DEMO_IDS          # pane name -> kitty window id, "deck" included
typeset -ga DEMO_CREATED      # ids of windows the demo opened, oldest first
typeset -g  DEMO_DRY=${DEMO_DRY:-0} DEMO_SLOW=${DEMO_SLOW:-1} DEMO_BEAT=${DEMO_BEAT:-}
typeset -g  DEMO_STATE=${DEMO_STATE:-${TMPDIR:-/tmp}/kitty-demo}
typeset -g  DEMO_TIMEOUT=${DEMO_TIMEOUT:-5}   # seconds a readiness poll may take
typeset -g  DEMO_LAYOUT=''                    # the deck tab's layout before the run

# The outside world, as functions the tests replace.
demo_kitten() { command kitten @ "$@" }
demo_hs()     { command hs -c "$1" }
demo_sleep()  { command sleep "$1" }

demo_err() { print -ru2 -- "beat ${DEMO_BEAT:-?} · $*"; return 1 }

# In a dry run print the command, quoted ((q+): newlines stay on one line),
# and succeed; otherwise fail so the caller goes on to do the real thing.
demo_dry() {
  (( DEMO_DRY )) || return 1
  print -r -- "${(j: :)${(q+)@}}"
}

demo_id() {
  [[ -n ${DEMO_IDS[$1]} ]] || { demo_err "no pane named $1"; return 1 }
  print -r -- ${DEMO_IDS[$1]}
}

# kitty --match for a pane name; "focused" is whichever window has focus.
demo_match() {
  if [[ $1 == focused ]]; then
    print -r -- state:focused
  else
    local id; id=$(demo_id $1) || return
    print -r -- id:$id
  fi
}

demo_lua_str() {
  local s=${1//\\/\\\\}
  print -r -- "\"${s//\"/\\\"}\""
}

# demo_poll WHAT CMD...: run CMD every 0.1 s until it succeeds, for at most
# DEMO_TIMEOUT seconds. For readiness only; pacing is beat-pause.
demo_poll() {
  local what=$1 i; shift
  for (( i = 0; i < DEMO_TIMEOUT * 10; i++ )); do
    "$@" && return 0
    demo_sleep 0.1
  done
  demo_err "timed out after ${DEMO_TIMEOUT}s waiting for $what"
}

demo_window_exists() { demo_kitten ls --match id:$1 >/dev/null 2>&1 }
demo_kitten_match()  { demo_kitten ls --match "$1" >/dev/null 2>&1 }
demo_has_text()      { [[ $(demo_kitten get-text --match id:$1 2>/dev/null) == *"$2"* ]] }

# Quitting presenterm is how a viewer stops the show, so every verb that
# touches kitty checks the deck first.
demo_deck_alive() {
  demo_window_exists ${DEMO_IDS[deck]} || demo_err "the deck pane has gone; stopping"
}

# pane open NAME [LAUNCH-OPTION...] -- CMD...
#   Open a kitty window running CMD without taking focus (beats focus
#   explicitly), remember it as NAME and wait until kitty lists it.
#   LAUNCH-OPTIONs go to `kitten @ launch`: --location=vsplit|hsplit,
#   --type=tab, --type=os-window --os-window-title=T, --cwd=DIR.
# pane ensure NAME ... -- CMD...   open unless NAME is open (for --from/--only)
# pane close NAME                  close it; nothing to do if it isn't open
pane() {
  local sub=$1 name=$2; shift 2
  case $sub in
    ensure)
      [[ -n ${DEMO_IDS[$name]} ]] && return 0
      pane open $name "$@" ;;
    open)
      demo_dry pane open $name "$@" && { DEMO_IDS[$name]=dry-$name; return 0 }
      local -a opts
      while (( $# )) && [[ $1 != -- ]]; do opts+=($1); shift; done
      (( $# )) && shift
      (( $# )) || { demo_err "pane open $name: no command"; return 1 }
      demo_deck_alive || return
      local id
      id=$(demo_kitten launch --keep-focus --title "demo $name" $opts -- "$@") && [[ $id == <-> ]] \
        || { demo_err "pane open $name: kitty would not launch it"; return 1 }
      DEMO_IDS[$name]=$id
      DEMO_CREATED+=($id)
      demo_poll "pane $name to appear" demo_window_exists $id ;;
    close)
      demo_dry pane close $name && { unset "DEMO_IDS[$name]"; return 0 }
      local id=${DEMO_IDS[$name]}
      [[ -n $id ]] || return 0
      unset "DEMO_IDS[$name]"
      DEMO_CREATED=(${DEMO_CREATED:#$id})
      demo_kitten close-window --match id:$id >/dev/null 2>&1 \
        || demo_err "pane close $name: kitty could not close window $id" ;;
    *)
      demo_err "pane: unknown subcommand $sub" ;;
  esac
}

# focus NAME: keyboard focus to NAME, switching tab or OS window if need be.
focus() {
  demo_dry focus "$@" && return 0
  local id; id=$(demo_id $1) || return
  demo_deck_alive || return
  demo_kitten focus-window --match id:$id >/dev/null || demo_err "focus $1 failed"
}

# keys NAME KEY...: key presses (kitty names: end, ctrl+end, ctrl+f) straight
# to NAME's program, bypassing kitty's own shortcuts.
keys() {
  demo_dry keys "$@" && return 0
  local match; match=$(demo_match $1) || return
  shift
  demo_deck_alive || return
  demo_kitten send-key --match $match "$@" >/dev/null || demo_err "keys $*: send-key failed"
}

# type-text NAME TEXT: TEXT to NAME's program as if typed. kitty interprets
# escapes in it, so a literal \r (in single quotes) is Enter.
type-text() {
  demo_dry type-text "$@" && return 0
  local match; match=$(demo_match $1) || return
  demo_deck_alive || return
  demo_kitten send-text --match $match -- "$2" >/dev/null || demo_err "type-text $1 failed"
}

# wait-text NAME TEXT: wait until TEXT is on NAME's screen.
wait-text() {
  demo_dry wait-text "$@" && return 0
  local id; id=$(demo_id $1) || return
  demo_poll "'$2' in pane $1" demo_has_text $id "$2"
}

# wait-window MATCH: wait until a kitty window matches MATCH (kitty match
# syntax, e.g. "state:focused and cmdline:micro").
wait-window() {
  demo_dry wait-window "$@" && return 0
  demo_poll "a window matching $1" demo_kitten_match "$1"
}

# slide goto N TEXT: show deck slide N (1-based; presenterm's "<N>G") and
# wait until TEXT is on screen.
slide() {
  [[ $1 == goto ]] || { demo_err "slide: unknown subcommand $1"; return 1 }
  demo_dry slide "$@" && return 0
  type-text deck "${2}G" && wait-text deck "$3"
}

# beat-pause SECONDS: pacing, scaled by play --slow.
beat-pause() {
  demo_dry beat-pause "$@" && return 0
  demo_sleep $(( $1 * DEMO_SLOW ))
}

# Start of a real run: the deck's tab goes to the splits layout (beats use
# vsplit/hsplit) and Hammerspoon pins the focused kitty OS window, centres it
# at 1600x1000 points, parks the pointer in it and arms the abort hotkey,
# which signals the pid in PIDFILE.
demo_begin() {
  local deck=${DEMO_IDS[deck]} pidfile=$1
  DEMO_LAYOUT=$(demo_kitten ls --match id:$deck \
    | jq -r ".[].tabs[] | select(any(.windows[]; .id == $deck)) | .layout") \
    && [[ -n $DEMO_LAYOUT ]] || { demo_err "cannot read the deck tab's layout"; return 1 }
  demo_kitten goto-layout --match window_id:$deck splits >/dev/null \
    || { demo_err "cannot switch to the splits layout (is it in enabled_layouts?)"; return 1 }
  [[ $(demo_hs "return demoStage.begin($(demo_lua_str $pidfile), 1600, 1000)") == ok ]] \
    || { demo_err "Hammerspoon could not pin the kitty window"; return 1 }
}

# Close every window the demo opened, newest first (ones already gone are
# fine), then restore the deck tab's layout and the window frame. Runs from
# play's EXIT trap, so it always succeeds.
demo_cleanup() {
  local id deck=${DEMO_IDS[deck]}
  for id in ${(Oa)DEMO_CREATED}; do
    demo_kitten close-window --match id:$id >/dev/null 2>&1
  done
  DEMO_CREATED=()
  DEMO_IDS=(deck "$deck")
  if [[ -n $DEMO_LAYOUT ]]; then
    demo_kitten goto-layout --match window_id:$deck $DEMO_LAYOUT >/dev/null 2>&1
  fi
  demo_hs 'return demoStage.finish()' >/dev/null 2>&1
  return 0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh kitty/demo/tests/demo-tests.zsh`
Expected: all PASS, exit 0.

- [ ] **Step 5: Commit**

```bash
git add kitty/demo/lib.zsh kitty/demo/tests/demo-tests.zsh
git commit -m "kitty demo: core verbs, run state and cleanup

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Self-describing panes (`card`) and their verbs

**Files:**
- Create: `kitty/demo/card` (executable)
- Modify: `kitty/demo/lib.zsh` (append `card`, `bell`, `demo_card_write`)
- Test: `kitty/demo/tests/demo-tests.zsh` (new section)

**Interfaces:**
- Consumes: `pane`, `demo_dry`, `demo_id`, `demo_poll`, `demo_err`, `DEMO_STATE`, `DEMO_ROOT` (Task 3).
- Produces:
  - Program: `card NAME` — shows `$DEMO_STATE/card-NAME.msg` centred and bold, redraws when it changes, writes its pid to `$DEMO_STATE/card-NAME.pid` (removed on HUP/TERM/INT), rings BEL on SIGUSR1. Function `card_render COLS LINES TEXT` (sourceable).
  - Verbs: `card open NAME TEXT [LAUNCH-OPTION…]`, `card ensure NAME TEXT [LAUNCH-OPTION…]`, `card say NAME TEXT`, `bell NAME`.

- [ ] **Step 1: Write the failing tests**

Insert above `# (later tasks add sections above this line)`:

```zsh
# --- card ---------------------------------------------------------------------
source $DEMO_ROOT/card
is 'card centres one line'   "$(card_render 20 5 hi)" $'\e[2J\e[3;10H\e[1mhi\e[22m'
is 'card centres a block'    "$(card_render 10 6 $'ab\ncdef')" $'\e[2J\e[3;5H\e[1mab\e[22m\e[4;4H\e[1mcdef\e[22m'
is 'overlong line starts at column 1' "$(card_render 4 1 abcdefgh)" $'\e[2J\e[1;1H\e[1mabcdefgh\e[22m'

mkdir -p $T/cardstate
DEMO_STATE=$T/cardstate $DEMO_ROOT/card T >$T/card.out 2>&1 </dev/null &
cardpid=$!
for i in {1..30}; do [[ -s $T/cardstate/card-T.pid ]] && break; sleep 0.1; done
is 'card writes its pid' "$(<$T/cardstate/card-T.pid)" $cardpid
print -r -- 'hello there' >| $T/cardstate/card-T.msg
sleep 0.4
[[ $(<$T/card.out) == *'hello there'* ]] && ok 'card shows new text' || bad 'card did not redraw'
kill -USR1 $cardpid; sleep 0.4
[[ $(<$T/card.out) == *$'\a'* ]] && ok 'card rings on USR1' || bad 'card did not ring'
kill -TERM $cardpid; wait $cardpid 2>/dev/null
[[ -e $T/cardstate/card-T.pid ]] && bad 'card left its pid file' || ok 'card removes its pid file'

reset_stubs
card open A 'Ringing in 3…' --location=vsplit && ok 'card open succeeds' || bad 'card open failed'
is 'card open writes the message'   "$(<$DEMO_STATE/card-A.msg)" 'Ringing in 3…'
is 'card open launches card' "$(grep '^launch' $T/kcalls)" "launch --keep-focus --title demo A --location=vsplit -- env DEMO_STATE=$DEMO_STATE $DEMO_ROOT/card A"
card say A 'Ringing in 2…'
is 'card say rewrites the message'  "$(<$DEMO_STATE/card-A.msg)" 'Ringing in 2…'
card say nosuch hi 2>/dev/null && bad 'card say to an unknown pane accepted' || ok 'card say needs an open card'
card ensure A 'other' --location=vsplit
is 'card ensure leaves an open card alone' "$(grep -c '^launch' $T/kcalls)" 1
got_usr1=0; trap 'got_usr1=1' USR1
print $$ >| $DEMO_STATE/card-A.pid
bell A && ok 'bell succeeds' || bad 'bell failed'
is 'bell signals the card' $got_usr1 1
trap - USR1
rm -f $DEMO_STATE/card-A.pid
bell A 2>/dev/null && bad 'bell without a running card accepted' || ok 'bell needs a running card'
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh kitty/demo/tests/demo-tests.zsh`
Expected: `no such file or directory: .../card`, FAILs in the card section; exit 1.

- [ ] **Step 3: Implement `kitty/demo/card`** (then `chmod +x kitty/demo/card`)

```zsh
#!/usr/bin/env zsh
# card NAME: a kitty demo pane that describes itself. Shows the text in
# $DEMO_STATE/card-NAME.msg centred and bold, redrawing whenever it (or the
# pane's size) changes; lib.zsh's `card say` rewrites it. SIGUSR1 rings the
# terminal bell (`bell`). The pid is in $DEMO_STATE/card-NAME.pid while it runs.

# card_render COLUMNS LINES TEXT: clear the screen and draw TEXT's lines, each
# centred, the block centred vertically.
card_render() {
  local cols=$1 lines=$2 text=$3 out=$'\e[2J' i row col
  local -a rows=("${(@f)text}")
  local top=$(( (lines - $#rows) / 2 ))
  (( top < 0 )) && top=0
  for (( i = 1; i <= $#rows; i++ )); do
    row=${rows[i]}
    col=$(( (cols - ${#row}) / 2 + 1 ))
    (( col < 1 )) && col=1
    out+=$'\e['$(( top + i ))';'$col$'H\e[1m'$row$'\e[22m'
  done
  print -rn -- $out
}

card_main() {
  local name=$1 dir=${DEMO_STATE:-${TMPDIR:-/tmp}/kitty-demo}
  local msg=$dir/card-$1.msg pidfile=$dir/card-$1.pid shown= now size
  mkdir -p $dir
  print -r -- $$ >| $pidfile
  trap 'print -n "\a"' USR1
  trap 'rm -f $pidfile; exit 0' HUP TERM INT
  print -n $'\e[?25l'                          # no cursor on a card
  while true; do
    now=$(<$msg 2>/dev/null)
    size=$(stty size 2>/dev/null) || size='24 80'
    if [[ "$size|$now" != "$shown" ]]; then
      shown="$size|$now"
      card_render ${size#* } ${size% *} "$now"
    fi
    sleep 0.1
  done
}

[[ $ZSH_EVAL_CONTEXT == toplevel ]] && card_main "$@"
```

- [ ] **Step 4: Append the card verbs to `kitty/demo/lib.zsh`**

```zsh
# card open NAME TEXT [LAUNCH-OPTION...]   a pane running ./card, showing TEXT
# card ensure NAME TEXT [LAUNCH-OPTION...] open unless NAME is open
# card say NAME TEXT                       change what it shows
card() {
  local sub=$1 name=$2 text=$3; shift 3
  case $sub in
    ensure)
      [[ -n ${DEMO_IDS[$name]} ]] && return 0
      card open $name $text "$@" ;;
    open)
      demo_dry card open $name $text "$@" && { DEMO_IDS[$name]=dry-$name; return 0 }
      demo_card_write $name $text || return
      rm -f $DEMO_STATE/card-$name.pid
      pane open $name "$@" -- env DEMO_STATE=$DEMO_STATE $DEMO_ROOT/card $name || return
      demo_poll "card $name to start" test -s $DEMO_STATE/card-$name.pid ;;
    say)
      demo_dry card say $name $text && return 0
      demo_id $name >/dev/null || return
      demo_card_write $name $text ;;
    *)
      demo_err "card: unknown subcommand $sub" ;;
  esac
}

demo_card_write() {
  mkdir -p $DEMO_STATE \
    && print -r -- $2 >| $DEMO_STATE/card-$1.msg.tmp \
    && mv -f $DEMO_STATE/card-$1.msg.tmp $DEMO_STATE/card-$1.msg \
    || demo_err "card $1: cannot write its message"
}

# bell NAME: NAME's card rings the terminal bell, so the bell comes from the
# pane's own program (kitty then fires bell-in-window for that pane).
bell() {
  demo_dry bell "$@" && return 0
  demo_id $1 >/dev/null || return
  local pid; pid=$(<$DEMO_STATE/card-$1.pid 2>/dev/null)
  [[ $pid == <-> ]] && kill -USR1 $pid 2>/dev/null || demo_err "bell $1: its card isn't running"
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `zsh kitty/demo/tests/demo-tests.zsh`
Expected: all PASS, exit 0.

- [ ] **Step 6: Commit**

```bash
git add kitty/demo/card kitty/demo/lib.zsh kitty/demo/tests/demo-tests.zsh
git commit -m "kitty demo: self-describing card panes and the bell

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Hammerspoon stage, mouse and window verbs

**Files:**
- Create: `kitty/demo/stage.lua`
- Modify: `kitty/demo/lib.zsh` (append `mouse`, `stage`, `demo_screen_point`, `demo_geometry`, `demo_glide`)
- Modify (manual, outside the repo): `~/.hammerspoon/init.lua`
- Test: `kitty/demo/tests/demo-tests.zsh` (new section)

**Interfaces:**
- Consumes: Task 1 geometry functions; Task 2 kitten path `$DEMO_ROOT/demo_geometry.py`; Task 3 helpers.
- Produces:
  - Lua global `demoStage` with `begin(pidPath, w, h)`, `frame()` (JSON), `placeBeside(title)`, `glide(x, y, ms)`, `click(mods)`, `notify(text)`, `abort()`, `finish()`, `selftest()`. Each returns `"ok"` (or JSON for `frame`/`selftest`) on success, an explanation otherwise.
  - Verbs: `mouse glide NAME XPCT YPCT [MS]`, `mouse glide-text NAME TEXT [MS]`, `mouse click [cmd]`, `stage place-beside TITLE`. Mouse targets must be panes in the main (pinned) OS window.

- [ ] **Step 1: Write the failing tests**

Insert above `# (later tasks add sections above this line)`:

```zsh
# --- mouse and stage ------------------------------------------------------------
reset_stubs
KGEOM=$GEOM HSFRAME=$FRAME
DEMO_IDS[A]=5 DEMO_IDS[B]=6
mouse glide A 50 50 && ok 'mouse glide succeeds' || bad 'mouse glide failed'
is 'mouse glide moves to the pane point' "$(grep glide $T/hcalls)" 'return demoStage.glide(500, 578, 700)'
: >| $T/hcalls
KSCREEN=$'$ rg TODO\n\nxx make it sparkle'
mouse glide-text B 'make it sparkle' 900
is 'mouse glide-text aims at the text' "$(grep glide $T/hcalls)" 'return demoStage.glide(970, 128, 900)'
: >| $T/hcalls
mouse glide-text B 'not on screen' 2>$T/err && bad 'glide-text to absent text accepted' || ok 'glide-text to absent text fails'
[[ $(<$T/err) == *"'not on screen' is not on screen"* ]] && ok 'absent-text message' || bad "absent-text message: $(<$T/err)"
grep -q glide $T/hcalls && bad 'pointer moved towards absent text' || ok 'pointer stays put for absent text'
DEMO_IDS[Z]=99
mouse glide Z 50 50 2>/dev/null && bad 'glide into an unknown window accepted' || ok 'glide into an unknown window fails'
grep -q glide $T/hcalls && bad 'pointer moved for an unknown window' || ok 'pointer stays put for an unknown window'
mouse click cmd
is 'mouse click passes modifiers' "$(grep click $T/hcalls)" 'return demoStage.click({"cmd"})'
: >| $T/hcalls
mouse click
is 'plain mouse click' "$(grep click $T/hcalls)" 'return demoStage.click({})'
stage place-beside 'kitty demo W'
is 'stage place-beside' "$(grep placeBeside $T/hcalls)" 'return demoStage.placeBeside("kitty demo W")'
HSREPLY='no window titled kitty demo W' DEMO_TIMEOUT=0.2 stage place-beside 'kitty demo W' 2>/dev/null \
  && bad 'place-beside without the window accepted' || ok 'place-beside waits, then fails'
KGEOM= HSFRAME=
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh kitty/demo/tests/demo-tests.zsh`
Expected: `command not found: mouse` / FAILs in this section; exit 1.

- [ ] **Step 3: Append the verbs to `kitty/demo/lib.zsh`**

```zsh
# mouse glide NAME XPCT YPCT [MS]   ease the pointer to a point in NAME (0..100)
# mouse glide-text NAME TEXT [MS]   ...to the first character of TEXT on NAME's screen
# mouse click [cmd]                 left click where the pointer is
# The pointer moves with real events, so kitty's spotlight and ripple react.
# NAME must be a pane in the main OS window (the one demo_begin pinned).
mouse() {
  demo_dry mouse "$@" && return 0
  local sub=$1; shift
  demo_deck_alive || return
  local id point pos
  case $sub in
    glide)
      id=$(demo_id $1) || return
      point=$(demo_screen_point $id pane $2 $3) || return
      demo_glide ${=point} ${4:-700} ;;
    glide-text)
      id=$(demo_id $1) || return
      pos=$(demo_find_text "$(demo_kitten get-text --match id:$id)" "$2") \
        || { demo_err "mouse glide-text $1: '$2' is not on screen"; return 1 }
      point=$(demo_screen_point $id cell ${=pos}) || return
      demo_glide ${=point} ${3:-700} ;;
    click)
      local mods='{}'
      [[ -n $1 ]] && mods="{\"$1\"}"
      [[ $(demo_hs "return demoStage.click($mods)") == ok ]] || { demo_err "mouse click failed"; return 1 }
      demo_sleep 0.1 ;;
    *)
      demo_err "mouse: unknown subcommand $sub" ;;
  esac
}

# demo_screen_point ID pane XPCT YPCT | ID cell ROW COL -> "x y" in screen points
demo_screen_point() {
  local id=$1 kind=$2 geom frame point
  geom=$(demo_geometry) || return
  frame=$(demo_hs 'return demoStage.frame()') && [[ $frame == \{* ]] \
    || { demo_err "Hammerspoon has no frame for the kitty window"; return 1 }
  if [[ $kind == pane ]]; then
    point=$(demo_point_in_pane $geom $frame $id $3 $4)
  else
    point=$(demo_point_at_cell $geom $frame $id $3 $4)
  fi
  [[ -n $point ]] || { demo_err "no geometry for window $id"; return 1 }
  print -r -- $point
}

# Every window's pixel rectangle, from the geometry kitten inside kitty.
demo_geometry() {
  local out=$DEMO_STATE/geometry.json
  mkdir -p $DEMO_STATE && rm -f $out
  demo_kitten kitten $DEMO_ROOT/demo_geometry.py $out >/dev/null 2>&1 \
    || { demo_err "the geometry kitten failed to run"; return 1 }
  demo_poll "the geometry kitten's output" test -s $out || return
  print -r -- "$(<$out)"
}

# demo_glide X Y MS: start the glide and wait for it to finish.
demo_glide() {
  [[ $(demo_hs "return demoStage.glide($1, $2, $3)") == ok ]] || { demo_err "mouse glide failed"; return 1 }
  demo_sleep $(( $3 / 1000.0 + 0.05 ))
}

demo_place_beside() { [[ $(demo_hs "return demoStage.placeBeside($(demo_lua_str $1))") == ok ]] }

# stage place-beside TITLE: float the OS window titled TITLE over the right of
# the main window, so both are in shot. Waits for it to appear.
stage() {
  demo_dry stage "$@" && return 0
  [[ $1 == place-beside ]] || { demo_err "stage: unknown subcommand $1"; return 1 }
  demo_poll "an OS window titled '$2'" demo_place_beside $2
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh kitty/demo/tests/demo-tests.zsh`
Expected: all PASS, exit 0.

- [ ] **Step 5: Implement `kitty/demo/stage.lua`**

```lua
-- demoStage: the Hammerspoon half of kitty/demo (see README.md there).
-- play drives it through the hs CLI: it pins and frames the kitty window,
-- glides and clicks the pointer with real mouse events (so kitty's spotlight
-- and ripple shaders see them) and arms an abort hotkey for the run.
-- Functions return "ok" (or JSON) on success, an explanation otherwise.

local M = {}

local main, savedFrame, pidFile, glideTimer, abortKey
local events = hs.eventtap.event

local function postMove(p)
  events.newMouseEvent(events.types.mouseMoved, p):post()
end

local function stopGlide()
  if glideTimer then glideTimer:stop(); glideTimer = nil end
end

-- Pin the focused (kitty) window, centre it at w x h points on its screen,
-- park the pointer in its middle and arm Ctrl+Alt+Cmd+. to abort the run.
function M.begin(pidPath, w, h)
  main = hs.window.focusedWindow()
  if not main then return "no focused window" end
  pidFile = pidPath
  savedFrame = main:frame()
  local s = main:screen():frame()
  w, h = math.min(w, s.w), math.min(h, s.h)
  main:setFrame({x = s.x + (s.w - w) / 2, y = s.y + (s.h - h) / 2, w = w, h = h}, 0)
  local f = main:frame()
  postMove({x = f.x + f.w / 2, y = f.y + f.h / 2})
  abortKey = abortKey or hs.hotkey.bind({"ctrl", "alt", "cmd"}, ".", M.abort)
  return "ok"
end

function M.frame()
  if not main then return "no pinned window" end
  local f = main:frame()
  return hs.json.encode({x = f.x, y = f.y, w = f.w, h = f.h})
end

-- Float the window titled `title` over the right part of the pinned one.
function M.placeBeside(title)
  local win = hs.window.get(title)
  if not (main and win) then return "no window titled " .. title end
  local f = main:frame()
  win:setFrame({x = f.x + f.w * 0.55, y = f.y + f.h * 0.15, w = f.w * 0.4, h = f.h * 0.55}, 0)
  return "ok"
end

-- Ease (in-out) the pointer to (x, y) over ms milliseconds, at about 60 Hz.
function M.glide(x, y, ms)
  stopGlide()
  local from = hs.mouse.absolutePosition()
  local start, dur = hs.timer.secondsSinceEpoch(), math.max(ms or 700, 1) / 1000
  glideTimer = hs.timer.doEvery(1 / 60, function()
    local t = math.min((hs.timer.secondsSinceEpoch() - start) / dur, 1)
    local e = t < 0.5 and 2 * t * t or 1 - (-2 * t + 2) ^ 2 / 2
    postMove({x = from.x + (x - from.x) * e, y = from.y + (y - from.y) * e})
    if t >= 1 then stopGlide() end
  end)
  return "ok"
end

-- Left click at the pointer, with modifiers such as {"cmd"}.
function M.click(mods)
  local p = hs.mouse.absolutePosition()
  events.newMouseEvent(events.types.leftMouseDown, p, mods or {}):post()
  hs.timer.usleep(40000)
  events.newMouseEvent(events.types.leftMouseUp, p, mods or {}):post()
  return "ok"
end

function M.notify(text)
  hs.notify.new({title = "kitty demo", informativeText = text}):send()
  return "ok"
end

-- Stop gliding and signal play's director; its trap then cleans up.
function M.abort()
  stopGlide()
  local f = pidFile and io.open(pidFile)
  if not f then return "not running" end
  local pid = f:read("l")
  f:close()
  if pid and pid:match("^%d+$") then os.execute("kill -TERM " .. pid) end
  return "ok"
end

-- End of a run (play's cleanup): restore the frame and disarm the hotkey.
function M.finish()
  stopGlide()
  if main and savedFrame then main:setFrame(savedFrame, 0) end
  if abortKey then abortKey:delete(); abortKey = nil end
  main, savedFrame, pidFile = nil, nil, nil
  return "ok"
end

-- Setup check, from a kitty pane:  hs -c 'return demoStage.selftest()'
-- Pins the focused window, glides the pointer round a 200-point square in
-- its middle, and reports the frame and whether Accessibility is granted.
function M.selftest()
  main = hs.window.focusedWindow()
  if not main then return "no focused window" end
  local f = main:frame()
  local cx, cy = f.x + f.w / 2, f.y + f.h / 2
  local corners = {{cx - 100, cy - 100}, {cx + 100, cy - 100}, {cx + 100, cy + 100}, {cx - 100, cy + 100}}
  local i = 0
  hs.timer.doUntil(function() return i >= #corners end, function()
    i = i + 1
    M.glide(corners[i][1], corners[i][2], 300)
  end, 0.4)
  return hs.json.encode({frame = {x = f.x, y = f.y, w = f.w, h = f.h}, accessibility = hs.accessibilityState()})
end

return M
```

- [ ] **Step 6 (manual): Wire it into Hammerspoon**

Append to `~/.hammerspoon/init.lua` (this is the user's file outside the repo; show the diff and get their OK before editing):

```lua
-- kitty/demo (project-tools): pointer and window control for the shader demo.
require("hs.ipc")
demoStage = dofile(os.getenv("HOME") .. "/github.com/garethrowlands/project-tools/kitty/demo/stage.lua")
```

Then the user: reloads Hammerspoon; in the Hammerspoon console runs `hs.ipc.cliInstall("/opt/homebrew")` once; confirms `which hs` prints `/opt/homebrew/bin/hs`.

- [ ] **Step 7 (manual): Self-test from a kitty pane**

Run: `hs -c 'return demoStage.selftest()'`
Expected: JSON with the kitty window's frame and `"accessibility":true`; the pointer traces a square in the middle of the kitty window and the spotlight follows it. If the spotlight doesn't follow, the events aren't reaching kitty: stop and report.

Then: `hs -c 'return demoStage.click({})'` with the pointer over the kitty window → a ripple appears.

- [ ] **Step 8: Commit**

```bash
git add kitty/demo/stage.lua kitty/demo/lib.zsh kitty/demo/tests/demo-tests.zsh
git commit -m "kitty demo: Hammerspoon stage, mouse and window verbs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `play` — options, beat selection, pre-flight, director

**Files:**
- Create: `kitty/demo/play` (executable)
- Test: `kitty/demo/tests/demo-tests.zsh` (new section)

**Interfaces:**
- Consumes: everything in `lib.zsh` (Tasks 3–5).
- Produces:
  - CLI: `play [--from N | --only N] [--slow FACTOR] [--dry-run]`; exit 2 on bad usage or no beats selected, 1 on failed pre-flight.
  - Functions (sourceable): `demo_select_beats DIR FROM ONLY`, `demo_beat_number FILE`, `demo_run_beats FILE…`, `demo_source_beat FILE`, `demo_already_running PIDFILE`, `demo_preflight`, `demo_direct FILE…`, `demo_play_main ARGS…`.
  - Beat files: `beats/NN-name.zsh`, sourced in numeric order with ERR_RETURN; `DEMO_BEAT` is set to NN while one runs. Dry run prints `# beat N · name` before each beat's verbs.

- [ ] **Step 1: Write the failing tests**

Insert above `# (later tasks add sections above this line)`:

```zsh
# --- play -------------------------------------------------------------------------
source $DEMO_ROOT/play
mkdir -p $T/beats
for f in 00-a 01-b 10-c; do print "print ran-$f" >| $T/beats/$f.zsh; done
print 'not a beat' >| $T/beats/02-x.txt
is 'all beats, in numeric order' "$(demo_select_beats $T/beats 0 '' | xargs -n1 basename | paste -sd' ' -)" '00-a.zsh 01-b.zsh 10-c.zsh'
is '--from skips earlier beats'  "$(demo_select_beats $T/beats 1 '' | xargs -n1 basename | paste -sd' ' -)" '01-b.zsh 10-c.zsh'
is '--only picks one beat'       "$(demo_select_beats $T/beats 0 10 | xargs -n1 basename)" '10-c.zsh'
is '--only of a missing beat'    "$(demo_select_beats $T/beats 0 5)" ''

print 'print one' >| $T/beats/01-ok.zsh
print 'false\nprint after' >| $T/beats/02-bad.zsh
out=$(demo_run_beats $T/beats/01-ok.zsh $T/beats/02-bad.zsh 2>&1)
st=$?
[[ $out == *one* && $out != *after* && $st != 0 ]] && ok 'a failing verb ends the beat and the run' || bad "run_beats: status $st, output ${(q+)out}"

print $$ >| $T/pid
demo_already_running $T/pid && ok 'a live director is detected' || bad 'live director missed'
print 999999 >| $T/pid
demo_already_running $T/pid && bad 'a dead pid counted as running' || ok 'a dead pid is not running'
print junk >| $T/pid
demo_already_running $T/pid && bad 'junk pid counted as running' || ok 'junk pid is not running'
demo_already_running $T/nosuch && bad 'missing pid file counted as running' || ok 'missing pid file is not running'

zsh $DEMO_ROOT/play --from x >/dev/null 2>&1; is 'bad --from is a usage error' $? 2
zsh $DEMO_ROOT/play --bogus  >/dev/null 2>&1; is 'unknown option is a usage error' $? 2
zsh $DEMO_ROOT/play --dry-run --only 99 >/dev/null 2>&1; is 'no beats selected is a usage error' $? 2
```

(Sourcing `play` re-sources `lib.zsh`, which replaces the kitty/Hammerspoon stubs with the real functions. Every later section runs `play` as a subprocess in dry-run mode, so none of them needs the stubs; any new section that does must come before this one.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh kitty/demo/tests/demo-tests.zsh`
Expected: `no such file or directory: .../play`, FAILs in this section; exit 1.

- [ ] **Step 3: Implement `kitty/demo/play`** (then `chmod +x kitty/demo/play`)

```zsh
#!/usr/bin/env zsh
# play: the self-running kitty shader demo (see README.md).
#
#   play [--from N | --only N] [--slow FACTOR] [--dry-run]
#
# Run it in a kitty pane that is alone in its tab: after the pre-flight
# checks that pane becomes the presenterm deck, and a background director
# plays beats/NN-*.zsh against it. Its log is $TMPDIR/kitty-demo/play.log.
# Abort with Ctrl+Alt+Cmd+. (Hammerspoon) or by quitting presenterm.

setopt extended_glob
zmodload zsh/system
DEMO_ROOT=${${(%):-%x}:A:h}
source $DEMO_ROOT/lib.zsh

demo_usage() {
  print -r -- 'usage: play [--from N | --only N] [--slow FACTOR] [--dry-run]'
}

# demo_select_beats DIR FROM ONLY: beat files to run, in numeric order.
demo_select_beats() {
  local dir=$1 from=${2:-0} only=$3 f n
  for f in $dir/<->-*.zsh(Nn); do
    n=$(demo_beat_number $f)
    if [[ -n $only ]]; then
      (( n == only )) || continue
    else
      (( n >= from )) || continue
    fi
    print -r -- $f
  done
}

demo_beat_number() { print -r -- $(( 10#${${1:t}%%-*} )) }

# A failing verb returns from the beat (ERR_RETURN), and that ends the run.
demo_source_beat() {
  setopt local_options err_return
  source $1
}

demo_run_beats() {
  local f
  for f in "$@"; do
    DEMO_BEAT=$(demo_beat_number $f)
    print -r -- "# beat $DEMO_BEAT · ${${f:t:r}#*-}"
    demo_source_beat $f || return 1
  done
}

# demo_already_running PIDFILE: true if that pid is a live process.
demo_already_running() {
  local pid
  pid=$(<$1) 2>/dev/null || return 1
  [[ $pid == <-> ]] && kill -0 $pid 2>/dev/null
}

# Everything a run needs, checked before anything visible happens.
demo_preflight() {
  local ok=1 cmd deck=$KITTY_WINDOW_ID
  [[ -n $deck ]] || { print -u2 'play: run me in a kitty pane'; return 1 }
  if ! demo_kitten ls >/dev/null 2>&1; then
    print -u2 'play: kitten @ cannot reach kitty (allow_remote_control socket-only and listen_on in kitty.conf)'
    return 1
  fi
  [[ $(demo_kitten ls | jq "[.[].tabs[] | select(any(.windows[]; .id == $deck)) | .windows[]] | length") == 1 ]] \
    || { print -u2 'play: run me in a pane that is alone in its tab'; ok=0 }
  for cmd in presenterm micro eza rg jq hs; do
    (( $+commands[$cmd] )) || { print -u2 "play: $cmd is not on PATH"; ok=0 }
  done
  if (( $+commands[hs] )); then
    [[ $(demo_hs 'return demoStage ~= nil and hs.accessibilityState()' 2>/dev/null) == true ]] \
      || { print -u2 'play: Hammerspoon has no demoStage, or lacks Accessibility (see README)'; ok=0 }
  fi
  if demo_already_running $DEMO_STATE/play.pid; then
    print -u2 "play: already running (pid $(<$DEMO_STATE/play.pid))"
    ok=0
  fi
  grep -q '^custom_shaders gentle' ~/.config/kitty/kitty.conf 2>/dev/null \
    || print -u2 'play: warning: custom_shaders gentle is not in kitty.conf'
  (( ok ))
}

# The background half of a real run, from the moment presenterm starts.
demo_direct() {
  demo_begin $DEMO_STATE/play.pid && wait-text deck 'kitty, with shaders' && demo_run_beats "$@" && return 0
  demo_hs "return demoStage.notify($(demo_lua_str "kitty demo stopped at beat ${DEMO_BEAT:-?}: see $DEMO_STATE/play.log"))" >/dev/null 2>&1
  return 1
}

demo_play_main() {
  local from=0 only=
  local -a beats
  while (( $# )); do
    case $1 in
      --from)    from=$2; shift 2 ;;
      --only)    only=$2; shift 2 ;;
      --slow)    DEMO_SLOW=$2; shift 2 ;;
      --dry-run) DEMO_DRY=1; shift ;;
      -h|--help) demo_usage; return 0 ;;
      *)         demo_usage >&2; return 2 ;;
    esac
  done
  [[ $from == <-> && ( -z $only || $only == <-> ) && $DEMO_SLOW == [0-9.]## ]] \
    || { demo_usage >&2; return 2 }
  beats=( ${(f)"$(demo_select_beats $DEMO_ROOT/beats $from $only)"} )
  (( $#beats )) || { print -u2 'play: no beats selected'; return 2 }

  if (( DEMO_DRY )); then
    DEMO_IDS[deck]=dry-deck
    demo_run_beats $beats
    return
  fi

  demo_preflight || return 1
  DEMO_IDS[deck]=$KITTY_WINDOW_ID
  mkdir -p $DEMO_STATE
  : >| $DEMO_STATE/play.log
  (
    print -r -- $sysparams[pid] >| $DEMO_STATE/play.pid
    # EXIT traps in zsh functions fire on return, so these live here, in the
    # subshell itself. HUP: the deck pane closed (presenterm quit).
    trap 'demo_cleanup; rm -f $DEMO_STATE/play.pid' EXIT
    trap 'exit 1' HUP INT TERM
    demo_direct $beats
  ) >>$DEMO_STATE/play.log 2>&1 </dev/null &!
  exec presenterm $DEMO_ROOT/deck.md
}

[[ $ZSH_EVAL_CONTEXT == toplevel ]] && { demo_play_main "$@"; exit }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh kitty/demo/tests/demo-tests.zsh`
Expected: all PASS, exit 0. (The `--dry-run --only 99` test needs `beats/` to exist or not; with no beats yet it still selects nothing → exit 2.)

- [ ] **Step 5: Commit**

```bash
git add kitty/demo/play kitty/demo/tests/demo-tests.zsh
git commit -m "kitty demo: play, the director

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Deck, scenes and beats 0–5

**Files:**
- Create: `kitty/demo/deck.md`
- Create: `kitty/demo/scene/comet.txt`
- Create: `kitty/demo/beats/00-intro.zsh`, `01-focus.zsh`, `02-tabs.zsh`, `03-cursor.zsh`, `04-spotlight.zsh`, `05-ripple.zsh`
- Test: `kitty/demo/tests/demo-tests.zsh` (new section)

**Interfaces:**
- Consumes: all verbs (Tasks 3–5), `play` (Task 6).
- Produces: slides 1–11 whose texts the beats wait on (table below); scene files.

| slide | beat | wait text |
|---|---|---|
| 1 | 0 | `kitty, with shaders` |
| 2 | 1 | `Focus follows you` |
| 3 | 2 | `switch tabs` |
| 4 | 3 | `cursor go?` |
| 5 | 4 | `spotlight` |
| 6 | 5 | `Clicks ripple` |
| 7 | 6 | `pane rang?` |
| 8 | 7 | `another tab` |
| 9 | 8 | `typing in?` |
| 10 | 9 | `land in a terminal app` |
| 11 | 10 | `gentle.pipeline` |

- [ ] **Step 1: Write the failing test**

Insert above `# (later tasks add sections above this line)`:

```zsh
# --- deck and beats ---------------------------------------------------------------
is 'deck has 11 slides' "$(grep -c '^<!-- end_slide -->' $DEMO_ROOT/deck.md)" 10
for text in 'kitty, with shaders' 'Focus follows you' 'switch tabs' 'cursor go?' 'spotlight' 'Clicks ripple' \
            'pane rang?' 'another tab' 'typing in?' 'land in a terminal app' 'gentle.pipeline'; do
  grep -qF -- $text $DEMO_ROOT/deck.md && ok "deck says '$text'" || bad "deck lacks '$text'"
done
dry=$(zsh $DEMO_ROOT/play --dry-run --only 1 2>&1)
is 'beat 1 dry-run shape' "$(print -r -- $dry | grep -v '^#' | awk '{print $1, $2}' | paste -sd, -)" \
  'slide goto,beat-pause 1.5,card open,focus A,beat-pause 2,card open,focus B,card say,beat-pause 2,focus deck,card say,card say,beat-pause 2.5'
zsh $DEMO_ROOT/play --dry-run --from 0 >/dev/null 2>&1 && ok 'every beat dry-runs' || bad 'a beat fails its dry run'
is 'comet.txt fits a half-width pane' "$(awk 'length > 60' $DEMO_ROOT/scene/comet.txt)" ''
(( $(wc -l < $DEMO_ROOT/scene/comet.txt) <= 35 )) && ok 'comet.txt fits a pane without scrolling' || bad 'comet.txt is too long'
[[ $(tail -1 $DEMO_ROOT/scene/comet.txt) == *'down at the bottom'* ]] && ok 'comet.txt ends at the bottom line' || bad 'comet.txt last line'
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh kitty/demo/tests/demo-tests.zsh`
Expected: FAILs in "deck and beats"; exit 1.

- [ ] **Step 3: Write `kitty/demo/deck.md`**

```markdown
<!-- jump_to_middle -->

kitty, with shaders
===================

everything you're about to see is live

<!-- end_slide -->

<!-- jump_to_middle -->

Focus follows you
=================

<!-- end_slide -->

<!-- jump_to_middle -->

…and when you switch tabs
=========================

<!-- end_slide -->

<!-- jump_to_middle -->

Where did the cursor go?
========================

<!-- end_slide -->

<!-- jump_to_middle -->

Your mouse gets a spotlight
===========================

<!-- end_slide -->

<!-- jump_to_middle -->

Clicks ripple
=============

<!-- end_slide -->

<!-- jump_to_middle -->

Which pane rang?
================

<!-- end_slide -->

<!-- jump_to_middle -->

…even in another tab
====================

<!-- end_slide -->

<!-- jump_to_middle -->

Which window am I typing in?
============================

<!-- end_slide -->

<!-- jump_to_middle -->

Click a link, land in a terminal app
====================================

<!-- end_slide -->

<!-- jump_to_middle -->

gentle.pipeline
===============

kitty ≥ 0.49 · custom_shaders
```

- [ ] **Step 4: Write `kitty/demo/scene/comet.txt`** (at most 35 lines so a half-width pane shows it without scrolling, none over 60 characters; `search hit` on a middle line, the bottom line last)

```
The cursor starts here. Next: the end of this line →

  kitty draws a comet from where the cursor was
  to where it is now, then lets it fade.

  Jumps of three cells or more get a trail;
  ordinary typing doesn't.

  It skips the trail when you change pane,
  so focus moves stay calm.




        …then to a search hit, right here.













…and now down at the bottom. Next: back to the top.
```

The file ends with a newline after the bottom line (29 lines).

- [ ] **Step 5: Write beats 0–5**

`kitty/demo/beats/00-intro.zsh`:
```zsh
# Beat 0: the deck alone, full window. Calm opening.
slide goto 1 'kitty, with shaders'
beat-pause 8
```

`kitty/demo/beats/01-focus.zsh`:
```zsh
# Beat 1: two panes split off; focus hops deck -> A -> B -> deck and each
# card says what is happening to it. A and B stay open for beat 2.
slide goto 2 'Focus follows you'
beat-pause 1.5
card open A $'New pane.\nI just got focus —\nsee my edges glow.' --location=vsplit
focus A
beat-pause 2
card open B $'Another one.\nNow I glow,\nand A is dimmed.' --location=hsplit
focus B
card say A $'Not focused any more,\nso I\'m slightly dimmed.'
beat-pause 2
focus deck
card say B $'Dimmed too.\nThe slides have focus.'
card say A $'Dimmed too.'
beat-pause 2.5
```

`kitty/demo/beats/02-tabs.zsh`:
```zsh
# Beat 2: a new tab glows on arrival; back to the deck's tab. C stays open
# in tab 2 for beat 7.
slide goto 3 'switch tabs'
beat-pause 1
card open C $'A whole new tab —\nit glowed on arrival.' --type=tab
focus C
beat-pause 2.5
focus deck
pane close A
pane close B
beat-pause 1.5
```

`kitty/demo/beats/03-cursor.zsh`:
```zsh
# Beat 3: micro on a file that narrates its own cursor jumps; the comet
# trail chases each one.
slide goto 4 'cursor go?'
pane open A --location=vsplit --cwd=$DEMO_ROOT/scene -- micro comet.txt
wait-text A 'The cursor starts here'
focus A
beat-pause 1.5
keys A end
beat-pause 1.5
keys A ctrl+end
beat-pause 1.5
keys A ctrl+home
beat-pause 1.5
keys A ctrl+f
type-text A 'search hit\r'
beat-pause 2
focus deck
pane close A
beat-pause 1
```

`kitty/demo/beats/04-spotlight.zsh`:
```zsh
# Beat 4: the pointer wanders slowly over the slide; the spotlight follows.
slide goto 5 'spotlight'
mouse glide deck 25 35 900
mouse glide deck 75 40 1400
mouse glide deck 60 75 1200
mouse glide deck 30 60 1200
beat-pause 1
```

`kitty/demo/beats/05-ripple.zsh`:
```zsh
# Beat 5: clicks on the deck (presenterm ignores them), each left to ripple.
slide goto 6 'Clicks ripple'
mouse glide deck 30 45 600
mouse click
beat-pause 1.2
mouse glide deck 70 35 600
mouse click
beat-pause 1.2
mouse glide deck 55 75 600
mouse click
beat-pause 1.5
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `zsh kitty/demo/tests/demo-tests.zsh`
Expected: all PASS, exit 0.

- [ ] **Step 7 (manual): Rehearse beats 0–5**

In a kitty pane alone in its tab: `kitty/demo/play --only 0`, then `--only 1` … `--only 5` (each ends back at the deck; quit presenterm with `q` between runs). Check against the spec's beat table: each effect is visible; the slide text matches what `slide goto` waits for (if presenterm renders a title differently, e.g. changes the ellipsis, update the wait text in the beat, not the deck); after each run `kitten @ ls` shows only the original pane. Tail `$TMPDIR/kitty-demo/play.log` for errors.

- [ ] **Step 8: Commit**

```bash
git add kitty/demo/deck.md kitty/demo/scene/comet.txt kitty/demo/beats kitty/demo/tests/demo-tests.zsh
git commit -m "kitty demo: deck and beats 0-5

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Beats 6–10 and the link scene

**Files:**
- Create: `kitty/demo/beats/06-bell.zsh`, `07-bell-tab.zsh`, `08-os-window.zsh`, `09-links.zsh`, `10-finale.zsh`
- Create: `kitty/demo/scene/repo/main.py`, `kitty/demo/scene/repo/README.md`, `kitty/demo/scene/repo/glitter/sparkle.txt`
- Test: `kitty/demo/tests/demo-tests.zsh` (new section)

**Interfaces:**
- Consumes: all verbs; slides 7–11 (Task 7).
- Produces: the complete show.

- [ ] **Step 1: Write the failing tests**

Insert above `# (later tasks add sections above this line)`:

```zsh
# --- beats 6-10 --------------------------------------------------------------------
dry=$(zsh $DEMO_ROOT/play --dry-run --only 6 2>&1)
is 'beat 6 dry-run shape' "$(print -r -- $dry | grep -v '^#' | awk '{print $1, $2}' | paste -sd, -)" \
  'slide goto,card open,beat-pause 1,card say,beat-pause 1,card say,beat-pause 1,bell A,card say,beat-pause 2.5,pane close'
dry=$(zsh $DEMO_ROOT/play --dry-run --only 7 2>&1)
is '--only 7 opens C itself' "$(print -r -- $dry | grep -v '^#' | sed -n 2p | awk '{print $1, $2, $3}')" 'card open C'
dry=$(zsh $DEMO_ROOT/play --dry-run --only 9 2>&1)
[[ $dry == *'mouse glide-text A '*'make it sparkle'* && $dry == *'mouse click cmd'* ]] \
  && ok 'beat 9 cmd-clicks the rg hit' || bad 'beat 9 does not cmd-click the rg hit'
is 'scene repo has one TODO' "$(rg -c TODO $DEMO_ROOT/scene/repo | paste -sd' ' -)" "$DEMO_ROOT/scene/repo/main.py:1"
grep -rq glitter $DEMO_ROOT/scene/repo/main.py && bad 'glitter appears in rg output' || ok 'glitter only in the eza listing'
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh kitty/demo/tests/demo-tests.zsh`
Expected: FAILs in "beats 6-10"; exit 1.

- [ ] **Step 3: Write the link scene**

`kitty/demo/scene/repo/main.py`:
```python
def shine():
    return "sparkle"


# TODO: make it sparkle
```

`kitty/demo/scene/repo/README.md`:
```markdown
# repo

A tiny tree for the kitty demo's link beat.
```

`kitty/demo/scene/repo/glitter/sparkle.txt`:
```
You got here by clicking a directory link.
```

- [ ] **Step 4: Write beats 6–10**

`kitty/demo/beats/06-bell.zsh`:
```zsh
# Beat 6: a pane counts down and rings while focus stays on the deck; only
# its edges flash.
slide goto 7 'pane rang?'
card open A 'Ringing in 3…' --location=vsplit
beat-pause 1
card say A 'Ringing in 2…'
beat-pause 1
card say A 'Ringing in 1…'
beat-pause 1
bell A
card say A $'Ding!\nOnly my edges flash —\nfocus never left the slides.'
beat-pause 2.5
pane close A
```

`kitty/demo/beats/07-bell-tab.zsh`:
```zsh
# Beat 7: C, in tab 2, rings: the whole tab area flashes and the tab title
# gets a bell. Then tab 2 goes.
slide goto 8 'another tab'
card ensure C $'A whole new tab —\nit glowed on arrival.' --type=tab
card say C $'I\'m in another tab.\nRinging in 3…'
beat-pause 1
card say C $'I\'m in another tab.\nRinging in 2…'
beat-pause 1
card say C $'I\'m in another tab.\nRinging in 1…'
beat-pause 1
bell C
beat-pause 2.5
pane close C
beat-pause 1
```

`kitty/demo/beats/08-os-window.zsh`:
```zsh
# Beat 8: a second OS window; focus alternates so one window pulses amber
# while the other dims, cools and vignettes.
slide goto 9 'typing in?'
card open W $'I\'m a separate kitty window.' --type=os-window --os-window-title='kitty demo W'
stage place-beside 'kitty demo W'
focus W
card say W $'I\'m a separate kitty window.\nI have focus:\nan amber edge ✦'
beat-pause 2.5
focus deck
card say W $'Not focused:\ndimmer, cooler,\nshadowed edges.'
beat-pause 2.5
focus W
card say W $'Focus again:\nthe amber edge pulses.'
beat-pause 2.5
focus deck
card say W $'And back.'
beat-pause 2
pane close W
beat-pause 1
```

`kitty/demo/beats/09-links.zsh`:
```zsh
# Beat 9: eza and rg print hyperlinks; Cmd+click on the rg hit opens micro at
# that line, Cmd+click on a directory cds the shell. Needs kitty-cd-link.zsh
# in the interactive zsh (see kitty/ and the install-scripts skill).
slide goto 10 'land in a terminal app'
pane open A --location=vsplit --cwd=$DEMO_ROOT/scene/repo -- zsh -i
focus A
type-text A 'clear; eza --hyperlink -1; rg --hyperlink-format=kitty TODO\r'
wait-text A 'make it sparkle'
beat-pause 1.5
mouse glide-text A 'make it sparkle' 900
mouse click cmd
wait-window 'state:focused and cmdline:micro'
beat-pause 2.5
keys focused ctrl+q
wait-window 'state:focused and not cmdline:micro'
beat-pause 1
mouse glide-text A 'glitter' 900
mouse click cmd
# the cd shows only in the prompt, which varies; give it a moment, then prove it
beat-pause 1
type-text A 'eza -1\r'
wait-text A 'sparkle.txt'
beat-pause 2.5
focus deck
pane close A
```

`kitty/demo/beats/10-finale.zsh`:
```zsh
# Beat 10: back to the deck alone; one last glide and click, then stillness.
slide goto 11 'gentle.pipeline'
mouse glide deck 50 60 1500
mouse click
beat-pause 6
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `zsh kitty/demo/tests/demo-tests.zsh`
Expected: all PASS, exit 0.

- [ ] **Step 6 (manual): Rehearse beats 6–10, then the whole show**

`kitty/demo/play --only 6` … `--only 10`, then `kitty/demo/play` and `kitty/demo/play --slow 2`. For beat 9, if the Cmd+click lands one row off, check the prompt height in `get-text` output against what's on screen (wide prompt glyphs shift columns, not rows); if `eza -1` still lists the repo rather than `sparkle.txt`, the `cd` hadn't happened yet: lengthen the `beat-pause 1` before it. Test the abort hotkey mid-beat and quitting presenterm mid-beat: both must leave only the original pane and the original window frame.

- [ ] **Step 7: Commit**

```bash
git add kitty/demo/beats kitty/demo/scene/repo kitty/demo/tests/demo-tests.zsh
git commit -m "kitty demo: beats 6-10 and the link scene

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: README, setup docs and acceptance takes

**Files:**
- Create: `kitty/demo/README.md`
- Modify: `CLAUDE.md` (Architecture list)
- Modify: `.claude/skills/install-scripts/SKILL.md` (append a section; the sandbox may need the user's permission to write under `.claude/skills/`)

**Interfaces:**
- Consumes: everything above.
- Produces: docs only.

- [ ] **Step 1: Write `kitty/demo/README.md`**

````markdown
# kitty shader demo

A self-running show-off of the custom shaders in `kitty/shaders/` (and the
link handling in `kitty/`), made to be screen-recorded. Run `play` in a kitty
pane that is alone in its tab: the pane becomes a presenterm deck, and a
background director opens and closes panes, a tab and a second OS window
around it, types into them and moves the real mouse pointer, so every effect
happens live. Stage panes describe themselves as they go.

Design: `docs/superpowers/specs/2026-10-04-kitty-shader-demo-design.md`.

## Setup (once)

1. kitty ≥ 0.49 with `custom_shaders gentle`, `allow_remote_control
   socket-only` and `listen_on` (already in this repo's kitty setup), and
   `kitty-cd-link.zsh` sourced by your zsh (for the link beat).
2. presenterm, micro, eza, rg and jq on PATH.
3. Hammerspoon, with Accessibility permission, and in `~/.hammerspoon/init.lua`:

   ```lua
   require("hs.ipc")
   demoStage = dofile(os.getenv("HOME") .. "/github.com/garethrowlands/project-tools/kitty/demo/stage.lua")
   ```

   Reload Hammerspoon, then in its console run `hs.ipc.cliInstall("/opt/homebrew")`
   once, so `hs` is on PATH.
4. Check from a kitty pane: `hs -c 'return demoStage.selftest()'` — the
   pointer traces a square in the kitty window with the spotlight following.

## Running

```
kitty/demo/play                 # the whole show (~100 s)
kitty/demo/play --only 6        # one beat
kitty/demo/play --from 6        # from beat 6 on
kitty/demo/play --slow 2        # every pause doubled
kitty/demo/play --dry-run       # print every verb, touch nothing
```

Start a screen recording (Cmd+Shift+5) first, then hands off. Abort with
**Ctrl+Alt+Cmd+.** or by quitting presenterm (`q`); either way the demo closes
everything it opened and restores the window frame and layout. The director's
log is `$TMPDIR/kitty-demo/play.log`; failures also show as a notification.

## Writing a beat

A beat is `beats/NN-name.zsh`, sourced in numeric order with ERR_RETURN, so
the first failing verb stops the run. Start each with `slide goto N TEXT` so
`--from`/`--only` work, and use `ensure` for panes an earlier beat would have
left open.

| Verb | Does |
|---|---|
| `slide goto N TEXT` | deck slide N; waits for TEXT |
| `pane open\|ensure NAME [launch options] -- CMD…` | new kitty window, without focus |
| `pane close NAME` | close it (no-op if not open) |
| `card open\|ensure NAME TEXT [launch options]` | a self-describing pane |
| `card say NAME TEXT` | change its text |
| `bell NAME` | that card rings the bell |
| `focus NAME` | keyboard focus there |
| `keys NAME KEY…` / `type-text NAME TEXT` | input to its program (`focused` = whichever has focus) |
| `wait-text NAME TEXT` / `wait-window MATCH` | readiness |
| `mouse glide NAME X% Y% [MS]` / `mouse glide-text NAME TEXT [MS]` / `mouse click [cmd]` | the real pointer |
| `stage place-beside TITLE` | float a second OS window over the main one |
| `beat-pause SECONDS` | pacing (scaled by `--slow`) |

## Tests

```
zsh kitty/demo/tests/demo-tests.zsh
kitty +launch kitty/demo/tests/test_demo_geometry.py
```

## Why a geometry kitten?

`kitten @ ls` reports panes' lines and columns but no pixel positions, so
`demo_geometry.py` runs inside kitty and reads `Window.geometry` and
`get_os_window_size()`. They are kitty internals: if a kitty upgrade breaks
them, the first mouse beat of a rehearsal fails with a clear message.
````

- [ ] **Step 2: Add the demo to CLAUDE.md's Architecture list**

After the `docs/ide-tools.md` bullet in `CLAUDE.md`:

```markdown
- **[kitty/demo/README.md](kitty/demo/README.md)** — `kitty/demo/play`: the self-running, screen-recordable show-off of the kitty shaders (presenterm deck + director driving kitty via `kitten @` and the mouse via Hammerspoon).
```

- [ ] **Step 3: Append to `.claude/skills/install-scripts/SKILL.md`**

```markdown
## Shader demo (optional)

`kitty/demo/play` needs Hammerspoon's CLI and the `demoStage` module. Add to
`~/.hammerspoon/init.lua`:

    require("hs.ipc")
    demoStage = dofile(os.getenv("HOME") .. "/github.com/garethrowlands/project-tools/kitty/demo/stage.lua")

reload Hammerspoon, run `hs.ipc.cliInstall("/opt/homebrew")` once in its
console, and check with `hs -c 'return demoStage.selftest()'` from a kitty
pane. Nothing is symlinked; run `play` from the repo. See kitty/demo/README.md.
```

- [ ] **Step 4: Run all suites**

Run: `zsh kitty/demo/tests/demo-tests.zsh && kitty +launch kitty/demo/tests/test_demo_geometry.py && zsh kitty/tests/kitty-cd-link-tests.zsh`
Expected: all PASS, exit 0.

- [ ] **Step 5 (manual): Acceptance takes**

Record two full takes with Cmd+Shift+5 and watch them back against the spec's success criteria: every effect visible at normal speed; nothing left behind (`kitten @ ls` shows only the original pane; window frame and layout restored); the pointer never leaves the kitty window(s); the two takes look the same.

- [ ] **Step 6: Commit**

```bash
git add kitty/demo/README.md CLAUDE.md .claude/skills/install-scripts/SKILL.md
git commit -m "kitty demo: README and setup docs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
