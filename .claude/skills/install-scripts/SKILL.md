---
name: install-scripts
description: Install this repo's zsh scripts (ide, close-project, switch-project, window, next-agent, tidy-windows, project-web, web, note) onto PATH via symlinks, set up kitty.conf for bin/window's live preview and key bindings, and install the kitty link handling in kitty/ (open_local.py, hint_menu.py, open-actions.conf, links.conf, kitty-cd-link.zsh) and the custom shader pipeline in kitty/shaders/. Use when setting up a new machine or adding a symlink for a newly added bin script.
---

## Installation

Symlink the executables onto your PATH:

```zsh
ln -s $PWD/zsh/bin/ide ~/.local/bin/ide
ln -s $PWD/zsh/bin/close-project ~/.local/bin/close-project
ln -s $PWD/zsh/bin/switch-project ~/.local/bin/switch-project
ln -s $PWD/zsh/bin/window ~/.local/bin/window
ln -s $PWD/zsh/bin/window-list ~/.local/bin/window-list
ln -s $PWD/zsh/bin/next-agent ~/.local/bin/next-agent
ln -s $PWD/zsh/bin/tidy-windows ~/.local/bin/tidy-windows
ln -s $PWD/zsh/bin/project-web ~/.local/bin/project-web
ln -s $PWD/zsh/bin/web ~/.local/bin/web
ln -s $PWD/zsh/bin/note ~/.local/bin/note
```

`tidy-windows` shells out to `python/tidy-windows-advise/advise` (resolved relative to the repo, no separate symlink needed) which requires `uv` to be installed, and `ANTHROPIC_API_KEY` set in the environment for AI-judged close/keep recommendations (it still works without a key, falling back to move-only/keep-only recommendations).

For `bin/window` live preview, enable socket-based remote control in `kitty.conf`:

```
allow_remote_control socket-only
listen_on unix:${HOME}/.config/kitty/kitty-{kitty_pid}.sock
```

Restrict the config directory so the socket is only accessible to you:

```zsh
chmod 700 ~/.config/kitty
```

Kitty key binding examples:

```
map kitty_mod+§       launch --type=overlay --cwd=current switch-project
map option+tab        launch --type=overlay --cwd=current window
map kitty_mod+shift+w launch --type=overlay --cwd=current tidy-windows
map kitty_mod+i       launch --type=overlay --cwd=current ide
map kitty_mod+n       launch --type=overlay --cwd=current note
map kitty_mod+b       launch --type=overlay --cwd=current project-web
map kitty_mod+j       launch --type=overlay --cwd=current next-agent
map kitty_mod+shift+j launch --type=overlay --cwd=current next-agent --prev
```

`window`'s "done, unseen" marker and `next-agent`'s jump to a finished agent need to know when you last looked at each window. Symlink the watcher that records it and enable it (kitty only attaches it to windows created after the config is loaded):

```zsh
ln -s $PWD/kitty/focus_watcher.py ~/.config/kitty/focus_watcher.py
echo 'watcher focus_watcher.py' >> ~/.config/kitty/kitty.conf
```

The same watcher drives the tab markers (`!` an agent in the tab is blocked, `✓` one has finished unseen, `…` one is working) and the "Claude needs you" / "Claude finished" desktop notifications. The markers also need `tab_bar.py`, and `{custom}` in place of `{activity_symbol}` and `{title}` in the tab title template in `kitty.conf` (`tab_bar.py` draws the activity symbol, leaving out agents' windows, then the marker and the title, shortening a path to `g/g/project-tools`):

```zsh
ln -s $PWD/kitty/tab_bar.py ~/.config/kitty/tab_bar.py
```

```
tab_title_template "{fmt.fg.red}{bell_symbol}{fmt.fg.tab}{custom}"
```

kitty loads a watcher file once and caches it by path, so after changing `focus_watcher.py` a config reload isn't enough. Either restart kitty, or — to keep your windows — symlink it under a fresh name, point the `watcher` line at that, and reload the config (Cmd+Ctrl+,):

```zsh
ln -s $PWD/kitty/focus_watcher.py ~/.config/kitty/agent_watcher.py   # then: watcher agent_watcher.py
```

## kitty link handling (`kitty/`)

Symlink the kittens and config into the kitty config directory (kitty follows the symlinks), include the mappings, and source the zsh side. Move any existing `~/.config/kitty/open-actions.conf` aside first — this one replaces it.

```zsh
for f in open_local.py hint_menu.py open-actions.conf links.conf; do
  ln -s $PWD/kitty/$f ~/.config/kitty/$f
done
echo 'include links.conf' >> ~/.config/kitty/kitty.conf
echo "source $PWD/kitty/kitty-cd-link.zsh" >> ~/.zshrc
```

Then reload kitty's config (Cmd+Ctrl+,) and start a new shell. Needs kitty's shell integration and `micro`, `glow`, `yazi` on `PATH`. See `docs/kitty-links.md`.

## kitty shaders (`kitty/shaders/`)

Symlink the pipeline and its local shaders into kitty's `shaders/` config directory and enable it (kitty 0.49+; the cursor trail group needs `cursor_trail` > 0 in `kitty.conf`). Move any existing files of the same names aside first.

```zsh
mkdir -p ~/.config/kitty/shaders
for f in gentle.pipeline cursor-trail-blaze-local.slang focus-highlight-local.slang os-window-focus-border.slang bell-ring.slang pond-ripple-local.slang spotlight-local.slang; do
  ln -s $PWD/kitty/shaders/$f ~/.config/kitty/shaders/$f
done
grep -q '^custom_shaders' ~/.config/kitty/kitty.conf || echo 'custom_shaders gentle' >> ~/.config/kitty/kitty.conf
# the bell shader only gets bell-in-window events with a visual bell; 0.01s keeps kitty's own flash invisible
grep -q '^visual_bell_duration' ~/.config/kitty/kitty.conf || echo 'visual_bell_duration 0.01' >> ~/.config/kitty/kitty.conf
```

Then reload kitty's config (Cmd+Ctrl+,).

## Shader demo (optional)

`kitty/demo/play` needs Hammerspoon's CLI and the `demoStage` module. Add to
`~/.hammerspoon/init.lua`:

    require("hs.ipc")
    demoStage = dofile(os.getenv("HOME") .. "/github.com/garethrowlands/project-tools/kitty/demo/stage.lua")

reload Hammerspoon, run `hs.ipc.cliInstall("/opt/homebrew")` once in its
console, and check with `hs -c 'return demoStage.selftest()'` from a kitty
pane. Nothing is symlinked; run `play` from the repo. See kitty/demo/README.md.
