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
