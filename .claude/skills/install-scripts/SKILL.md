---
name: install-scripts
description: Install this repo's zsh scripts (ide, close-project, switch-project, window, tidy-windows, project-web, web, note) onto PATH via symlinks, set up kitty.conf for bin/window's live preview and key bindings, and install the kitty link handling in kitty/ (open_local.py, hint_menu.py, open-actions.conf, links.conf, kitty-cd-link.zsh) and the custom shader pipeline in kitty/shaders/. Use when setting up a new machine or adding a symlink for a newly added bin script.
---

## Installation

Symlink the executables onto your PATH:

```zsh
ln -s $PWD/zsh/bin/ide ~/.local/bin/ide
ln -s $PWD/zsh/bin/close-project ~/.local/bin/close-project
ln -s $PWD/zsh/bin/switch-project ~/.local/bin/switch-project
ln -s $PWD/zsh/bin/window ~/.local/bin/window
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

Symlink the pipeline into kitty's `shaders/` config directory and enable it (kitty 0.49+; the cursor trail group needs `cursor_trail` > 0 in `kitty.conf`). Move any existing `~/.config/kitty/shaders/gentle.pipeline` aside first.

```zsh
mkdir -p ~/.config/kitty/shaders
ln -s $PWD/kitty/shaders/gentle.pipeline ~/.config/kitty/shaders/gentle.pipeline
grep -q '^custom_shaders' ~/.config/kitty/kitty.conf || echo 'custom_shaders gentle' >> ~/.config/kitty/kitty.conf
```

Then reload kitty's config (Cmd+Ctrl+,).
