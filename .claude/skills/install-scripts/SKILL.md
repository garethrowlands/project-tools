---
name: install-scripts
description: Install this repo's zsh scripts (ide, close-project, switch-project, window, next-agent, save-session, tidy-windows, project-web, web, note) onto PATH via symlinks, set up kitty.conf for bin/window's live preview and key bindings, and install the kitty link handling in kitty/ (open_local.py, hint_menu.py, open-actions.conf, links.conf, kitty-cd-link.zsh) and the custom shader pipeline in kitty/shaders/. Use when setting up a new machine or adding a symlink for a newly added bin script.
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
ln -s $PWD/zsh/bin/save-session ~/.local/bin/save-session
ln -s $PWD/zsh/bin/tidy-windows ~/.local/bin/tidy-windows
ln -s $PWD/zsh/bin/project-web ~/.local/bin/project-web
ln -s $PWD/zsh/bin/web ~/.local/bin/web
ln -s $PWD/zsh/bin/note ~/.local/bin/note
```

`tidy-windows` shells out to `python/tidy-windows-advise/advise` (resolved relative to the repo, no separate symlink needed) which requires `uv` to be installed, and `ANTHROPIC_API_KEY` set in the environment for AI-judged close/keep recommendations (it still works without a key, falling back to move-only/keep-only recommendations).

`save-session` is run by hand before quitting kitty; it writes `~/.config/kitty/sessions/restore.kitty-session`. To have kitty open that on starting, set in `kitty.conf` (needs kitty's shell integration, which is what resumes each Claude agent):

```
startup_session ~/.config/kitty/sessions/restore.kitty-session
```

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
tab_title_template "{fmt.fg.red}{bell_symbol}{fmt.fg.tab}{activity_symbol * 0}{custom}"
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
echo "source $PWD/zsh/functions/aliases.zsh" >> ~/.zshrc   # ls/rg/fd print hyperlinks
```

Then reload kitty's config (Cmd+Ctrl+,) and start a new shell. Needs kitty's shell integration and `micro`, `mdfried`, `yazi` on `PATH`. See `docs/kitty-links.md`.

## Colour theme (`kitty/themes/`, `zsh/functions/theme.zsh`)

The palette is Catppuccin Mocha with the crust background (`#11111B`), dark mode only. The theme lives in `kitty/themes/catppuccin-mocha-crust.conf` (deviations from the official file are commented in it); kitty's own theme files just include it by absolute path, so edit it in the repo. The files that have to live under `~/.config` are kept in `config/` and put in place by one idempotent script (a real file in the way is moved aside to `NAME.pre-symlink`; tests in `config/install-tests.zsh`):

```zsh
zsh config/install.zsh
```

It writes kitty's `current-theme.conf` and `dark-theme.auto.conf` (each an `include` of the repo theme), links `config/btop/themes/catppuccin_mocha.theme` and `config/mdfried/config.toml` (which sets `code_theme = "Catppuccin Mocha"`) into place, and sets `color_theme = "catppuccin_mocha"` in `btop.conf` in place, since btop rewrites that file itself.

`zsh/functions/theme.zsh` (sourced by `project.zsh`, `notes-lib.zsh` and `bin/tidy-windows`) sets `BAT_THEME=ansi` (bat follows the terminal's 16 colours) and Mocha colours in `FZF_DEFAULT_OPTS`. hunk is already `theme=catppuccin-mocha` in its own config. The shader colours (below) are Mocha's too, in linear RGB: lavender pane glow (matches `active_border_color`), peach OS-window glow and cursor trail, red bell, rosewater spotlight and ripple, and a dark slate for the unfocused window.

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

## Hammerspoon (`hammerspoon/`)

`hammerspoon/init.lua` holds the window positioning (Control+Option+arrow snaps to halves, crossing monitors; Return maximises; adding Command moves focus) and loads the shader demo's `demoStage`. Symlink it as Hammerspoon's config (move any existing `~/.hammerspoon/init.lua` aside first) and reload Hammerspoon:

```zsh
mkdir -p ~/.hammerspoon
ln -s $PWD/hammerspoon/init.lua ~/.hammerspoon/init.lua
```

Machine-specific or private settings go in `hammerspoon/local.lua`, which `init.lua` loads if present and git ignores. Never put secrets in `init.lua` itself.

## Shader demo (optional)

`kitty/demo/play` needs Hammerspoon's CLI and the `demoStage` module, which the config above already loads. Run `hs.ipc.cliInstall("/opt/homebrew")` once in the Hammerspoon console, and check with `hs -c 'return demoStage.selftest()'` from a kitty pane. Nothing else is symlinked; run `play` from the repo. See kitty/demo/README.md.
