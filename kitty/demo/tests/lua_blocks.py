"""Check that a Lua file's blocks balance: every function / if / do / repeat
is closed by end (or until), and no end is left over.

    python3 kitty/demo/tests/lua_blocks.py kitty/demo/stage.lua

There is no Lua interpreter outside Hammerspoon on this machine, so this is
the demo suite's guard against a stray or missing `end` in stage.lua (which
otherwise only shows up as a load error in the Hammerspoon console). Not a
parser: strings and comments are stripped, then keywords counted. Exits 1
with the offending line on imbalance.
"""

import re
import sys

LONG = re.compile(r'\[(=*)\[.*?\]\1\]', re.S)
TOKEN = re.compile(r'--\[(=*)\[.*?\]\1\]|--[^\n]*|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\'|\[(=*)\[.*?\]\2\]|[A-Za-z_]\w*|\n', re.S)
OPEN = {'function', 'if', 'do', 'repeat'}
CLOSE = {'end', 'until'}


def check(src: str) -> str:
    depth, line = 0, 1
    for m in TOKEN.finditer(src):
        tok = m.group(0)
        if tok == '\n':
            line += 1
            continue
        line += tok.count('\n')
        if tok in OPEN:
            depth += 1
        elif tok in CLOSE:
            depth -= 1
            if depth < 0:
                return f'line {line}: `{tok}` closes nothing'
    return '' if depth == 0 else f'end of file: {depth} block(s) left open'


if __name__ == '__main__':
    problem = check(open(sys.argv[1]).read())
    if problem:
        print(f'{sys.argv[1]}: {problem}')
        sys.exit(1)
