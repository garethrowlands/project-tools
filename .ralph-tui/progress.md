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

