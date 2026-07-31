---
name: install-scripts
description: Install this repo's zsh scripts (ide, close-project, switch-project, window, project-web, web, note) onto PATH via symlinks, and set up kitty.conf for bin/window's live preview and key bindings. Use when setting up a new machine or adding a symlink for a newly added bin script.
---

## Installation

Symlink the executables onto your PATH:

```zsh
ln -s $PWD/zsh/bin/ide ~/.local/bin/ide
ln -s $PWD/zsh/bin/close-project ~/.local/bin/close-project
ln -s $PWD/zsh/bin/switch-project ~/.local/bin/switch-project
ln -s $PWD/zsh/bin/window ~/.local/bin/window
ln -s $PWD/zsh/bin/project-web ~/.local/bin/project-web
ln -s $PWD/zsh/bin/web ~/.local/bin/web
ln -s $PWD/zsh/bin/note ~/.local/bin/note
```

For `bin/window` live preview, enable socket-based remote control in `kitty.conf`:

```
allow_remote_control yes
listen_on unix:${HOME}/.config/kitty/kitty-{kitty_pid}.sock
```

Restrict the config directory so the socket is only accessible to you:

```zsh
chmod 700 ~/.config/kitty
```

Kitty key binding example:

```
map kitty_mod+§ launch --type=overlay --cwd=current switch-project
```
