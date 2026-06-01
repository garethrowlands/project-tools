---
name: switch-project enhancements
description: Ongoing session adding fzf key bindings and kitty window preview to the project picker in project-tools
type: project
---

Working on `zsh/bin/switch-project` and `zsh/functions/project.zsh` in the project-tools repo.

**Why:** Improving the interactive project picker with richer UX — key bindings and a contextual preview pane.

**What's been done:**
- `ide` and `close-project` now accept an explicit path argument (file or dir)
- fzf picker bindings added: `ctrl-i` opens IDE, `ctrl-w` closes IDE via `close-project`, `ctrl-t` opens new tab, `ctrl-y` copies path
- Preview pane shows open kitty windows for the selected project (bold, with a full-width `─` divider using `FZF_PREVIEW_COLUMNS`), then README/CLAUDE.md/ls below
- Kitty ls JSON pre-fetched once at picker startup into a temp file to avoid hanging preview subprocesses
- `null` CWDs in kitty ls JSON guarded with `// empty` to prevent jq `startswith()` errors
- Tests in `zsh/functions/project-tests.zsh`

**Next task:** Put a `*` in front of each project label in the Open group in the fzf picker list.

**How to apply:** The picker list is built in `_project_build_list` (awk). The label field is field 2 in the tab-delimited output; `--with-nth 2` shows it. Open projects are printed at line ~118 of project.zsh.
