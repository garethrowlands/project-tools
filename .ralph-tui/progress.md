# Ralph Progress Log

This file tracks progress across iterations. Agents update this file
after each iteration and it's included in prompts for context.

## Codebase Patterns (Study These First)

**Tilde expansion in zsh parameter substitution**: `${var#~/}` expands `~/` to `$HOME/` in the pattern, so it strips nothing when `var="~/foo"`. Use `${var:2}` to strip the first two literal chars instead. Safe idiom:
```zsh
[[ "$r" == "~" ]]   && r="$HOME"
[[ "$r" == "~/"* ]] && r="$HOME/${r:2}"
```

**fzf group headers (non-selectable)**: Store entries as `PATH\tLABEL` with headers as `\t── Name ──` (empty PATH field). Use `--with-nth 2` to display only the label. Use `enter:transform([[ -n {1} ]] && echo "become(echo {1})")` so pressing enter on a header (empty `{1}`) is a no-op.

**Testable kitty-aware functions**: Pass `kitty_cwds` as a parameter to list-building functions rather than detecting kitty inside them. This makes unit tests possible without a kitty socket.

**jq cwd matching with empty foreground_processes**: Use `[.foreground_processes[].cwd] | map(condition) | any` rather than `select(any(generator; condition))` — the array approach handles empty arrays (returns false naturally) and avoids generator scoping issues.

---

## 2026-05-30 - pt-bun.5
- What was implemented: `switch-project` now `cd`s into the project path when kitty is unavailable or no matching window is found, instead of returning early. Added three tests: cd when kitty unavailable, cd when no matching window, no IDE opened on cd fallback.
- Files changed: `zsh/functions/project.zsh`, `zsh/tests/project-tests.zsh`
- **Learnings:**
  - To test `switch-project` without interactive fzf: shadow `project()` in test scope to return a fixed path, shadow `kitty()` to control availability; unfunction both after. This avoids any real socket or picker invocation.
  - `cd` inside a shell function affects the calling shell — no extra machinery needed, just call `cd "$project_path"`.
---

## 2026-05-30 - pt-bun.3
- What was implemented: `_switch_project_find_window` helper (cwd-first, window-title fallback, tab-title fallback) and `switch-project` command in `zsh/functions/project.zsh`. Six new tests in `zsh/tests/project-tests.zsh` using mock `kitty @ ls` JSON.
- Files changed: `zsh/functions/project.zsh`, `zsh/tests/project-tests.zsh`
- **Learnings:**
  - For testable kitty-aware functions, extract the window-finding logic into a pure helper `_switch_project_find_window(project_path, kitty_ls_json)` — tests supply mock JSON and never need a real kitty socket.
  - jq `[.foreground_processes[].cwd] | map(. == $path or startswith($path + "/")) | any` is the safe idiom: empty arrays evaluate to false, no generator scoping surprises.
  - Tab title fallback (`.[].tabs[] | select(.title | contains($name))`) catches cases where a window's title changes but the tab name still shows the project.
---

## 2026-05-30 - pt-bun.1
- What was implemented: `zsh/functions/project.zsh` — full `project()` command with `_project_cache_file`, `_project_expand_tilde`, `_project_parse_roots`, `_project_rel_label`, `_project_scan`, `_project_build_list`, `_project_picker` helpers. `zsh/tests/project-tests.zsh` — 29 tests covering all acceptance criteria.
- Files changed: `zsh/functions/project.zsh` (new), `zsh/tests/project-tests.zsh` (new)
- **Learnings:**
  - Zsh expands `~` in `${var#~/}` pattern, treating it as `$HOME/`. Use `${var:2}` (strip 2 chars) to avoid this.
  - fzf `transform` binding (added in fzf ~0.38) enables conditional actions: if transform outputs nothing, fzf stays open. This is the cleanest way to make header lines non-selectable.
  - `"${(@s/:/)VAR}"` splits on `:` without tilde-expanding elements; tilde must be handled manually after.
  - Tests directory at `zsh/tests/` is separate from `zsh/functions/`; source path is `"${0:A:h}/../functions/project.zsh"`.
---

