# `ide` opens a file at a line: design

Status: proposal, not yet built.

## Intent and why

`ide` opens the right IDE for a project, but only ever the project. Getting from a path and line number to that line — a stack trace, a grep hit, a compiler error, a talk's live demo — still means opening the project, then the file, then finding the line by hand.

The KEP talk (`atg-decom/context/build/talks/kep-track1/`) needed exactly this and grew its own script for it, now `jump`. Comparing the two showed the project-opening half is the same operation in both; the file-and-line half is general-purpose and belongs here. `jump` keeps its own copy anyway, so the presentation has no dependency on this repo.

Goal: `ide path/to/File.kt:42` opens the project and puts the cursor on line 42; `ide path` behaves exactly as now.

## Behaviour

```zsh
ide [path[:line[:column]]]
```

- A path with no `:line` opens the project, as today.
- A file with `:line` (and optionally `:column`) opens the file's project as today, then opens the file at that line in the same IDE.
- The project is still the file's git root, and the IDE is still chosen from that root's project files.
- A path that exists with a literal colon in its name is taken as a path, not as `path:line`: test the whole argument with `[[ -e ]]` before splitting on the last colon(s).
- A line number on a directory is an error, not silently ignored.

### IntelliJ

Open the project first, then the file. IntelliJ opens a file in a project only when that project is already open; otherwise it opens it in LightEdit, a separate bare editor. (IntelliJ's own command-line docs say so: <https://www.jetbrains.com/help/idea/opening-files-from-command-line.html>.)

1. `open -a "IntelliJ IDEA" "$project"`, as now. It reuses the running IntelliJ.
2. Jump with IntelliJ's URL scheme, `open "idea://open?file=<url-encoded absolute path>&line=<n>"`, with `n` counted from 1 as every editor shows it. The running instance handles it. IntelliJ registers `idea` in its `Info.plist` (`CFBundleURLTypes`, name `Stacktrace`).

Why not the alternatives:

- `open -a "IntelliJ IDEA" --args --line N file` — macOS passes `--args` only when it launches the app; when IntelliJ is already running, `--line` is silently dropped.
- The Toolbox `idea` shim (`idea --line N file`) — it runs `open -n`, starting an extra IntelliJ process per call, the reason `ide` stopped using it. It also wraps any argument containing a space in literal quote characters, so a path with a space (e.g. `POST v3-customers-{tenant}.md`) never resolves.

Open questions, to settle by trying them:

- Whether step 2 lands in LightEdit when step 1 is still loading a project IntelliJ didn't have open. `jump` sleeps one second between the steps; something better would wait for the project window (Hammerspoon, or polling `System Events` for a window titled with the project name).
- Whether the URL needs `project=` too when the same file is open in two projects.

### VS Code

`code --reuse-window "$project"`, then `code --reuse-window --goto "file:line[:column]"`. `--goto` is VS Code's native form, so no URL scheme is needed. It may work as a single call with both arguments; try that first.

## Paths through symlinks

Resolve the file with `${file:A}` before using it. A path reached through a symlink (the talk directory reaches the repos through an `ecommerce` symlink) isn't recognised by IntelliJ as inside the open project, and opens in LightEdit.

## What stays out

- Named locations, drift checks against expected text, and presenter cues stay in `jump`: they are about one talk, not about opening files.
- No new dependency beyond what `ide` already uses (`git`, `open`, `code`); URL-encoding can use `python3`, which macOS ships, or zsh's own parameter expansion.

## Docs to update when it's built

- `README.md`: the `ide` usage line and bullets.
- `docs/ide-tools.md`: the `bin/ide` entry.
- `kitty.conf`'s `kitty_mod+i` binding is unaffected: it passes no line.
