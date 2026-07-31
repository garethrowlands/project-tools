# project-tools

## `ide`

Opens the current project in the appropriate IDE.

```zsh
ide [path]
```

- Defaults to `$PWD` if no path is given
- When inside a git repo, opens at the repo root (not the subdirectory)
- Detects IntelliJ IDEA for Java/Gradle projects (`.idea/`, `pom.xml`, `build.gradle`); falls back to VS Code for everything else
- If the IDE is already running, focuses the existing window rather than opening a new instance

### Installation

```zsh
ln -s $PWD/zsh/bin/ide ~/.local/bin/ide
```

---

## `close-project`

Closes the IDE window for a project — the inverse of `ide`.

```zsh
close-project [path]
```

- Defaults to `$PWD` if no path is given
- Uses `System Events` + close-button click for VS Code (no AppleScript dictionary for it)
- When called with no argument, also closes the current kitty pane

### Installation

```zsh
ln -s $PWD/zsh/bin/close-project ~/.local/bin/close-project
```

---

## `project`

Interactive fuzzy picker for git projects.

```zsh
project [--refresh] [query]
```

- Searches for git repos under the directories listed in `$PROJECT_ROOTS` (colon-separated)
- Results are cached; pass `--refresh` to rescan
- In kitty, opens the picker in a new tab and returns the selected path to the calling shell
- Outputs the selected project path, so it can be used in scripts or other commands

### Configuration

```zsh
export PROJECT_ROOTS=~/code:~/work   # directories to scan for git repos
```

Cache is stored at `$XDG_CACHE_HOME/project-tools/projects.txt` by default, or overridden with `$PROJECT_CACHE`.

### Installation

Source `zsh/functions/project.zsh` in your `.zshrc`:

```zsh
source /path/to/project-tools/zsh/functions/project.zsh
```

---

## `switch-project`

Picks a project and switches to its kitty window.

```zsh
switch-project [query]
```

- Runs the `project` picker to select a project
- Finds an existing kitty window whose CWD is the project root (or a subdirectory) and focuses it
- If no matching window exists, opens a new kitty tab at the project root
- Intended to be bound to a kitty keyboard shortcut

### Installation

```zsh
ln -s $PWD/zsh/bin/switch-project ~/.local/bin/switch-project
```

---

## `window`

Fuzzy picker over all open kitty windows; focuses the one you pick.

```zsh
window
```

- Switches to `stack` layout for full-screen display, restores the previous layout on exit
- Preview pane shows the live screen content of the highlighted window
- `ctrl-t` moves the selected window to a new tab
- Requires `listen_on` in `kitty.conf` (see below) so the preview works from fzf's subprocess

### Installation

```zsh
ln -s $PWD/zsh/bin/window ~/.local/bin/window
```

Enable socket-based remote control in `kitty.conf`:

```
allow_remote_control yes
listen_on unix:${HOME}/.config/kitty/kitty-{kitty_pid}.sock
```

Restrict the config directory so the socket is only accessible to you:

```zsh
chmod 700 ~/.config/kitty
```

---

## `project-web`

Opens a project's web page (GitHub/GitLab repo, or its origin remote's URL) in the browser.

```zsh
project-web [path]
```

- Defaults to `$PWD` if no path is given; uses the git root
- If a Microsoft Edge tab already has that repo's URL (or a sub-page like an open issue/PR) open, focuses that tab/window instead of opening a new one
- Dispatches by the origin remote's host: GitLab remotes use `glab repo view -w`, GitHub remotes use `gh repo view -w`, anything else falls back to deriving an `https://` URL from the remote and opening it

### Installation

```zsh
ln -s $PWD/zsh/bin/project-web ~/.local/bin/project-web
```

---

## `web` / `note`

Fuzzy picker over your notes vault (`$HOME/notes`); `web` opens the note's `source`/`url` field in the browser, `note` opens the note itself in `$EDITOR`.

```zsh
web [query]
note [query]
```

- Switches to `stack` layout for full-screen display, restores the previous layout on exit
- `web` extracts the `source`/`url` frontmatter field from the picked note and opens it with `open`; errors if the note has no URL
- `note` opens the picked note directly in `$EDITOR` (defaults to `vim`)
- Intended to be bound to kitty keyboard shortcuts. For interactive-shell use instead, see the `web`/`note` functions in `functions/web.zsh`, which print an OSC 8 hyperlink rather than opening it directly

### Installation

```zsh
ln -s $PWD/zsh/bin/web ~/.local/bin/web
ln -s $PWD/zsh/bin/note ~/.local/bin/note
```
