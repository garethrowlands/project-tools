# theme.zsh — Catppuccin Mocha colours for the tools the pickers run (fzf, bat).
# Sourced by project.zsh, notes-lib.zsh and bin/tidy-windows rather than from
# ~/.zshrc, so the pickers get them even when kitty launched them without the
# shell's exports. Safe to source more than once.

# bat's "ansi" theme uses the terminal's own 16 colours, so it follows the
# kitty theme.
export BAT_THEME=${BAT_THEME:-ansi}

# fzf, from catppuccin/fzf (mocha), with the crust background used by kitty.
_theme_fzf_colors='--color=bg+:#313244,bg:#11111B,spinner:#F5E0DC,hl:#F38BA8'
_theme_fzf_colors+=' --color=fg:#CDD6F4,header:#F38BA8,info:#CBA6F7,pointer:#F5E0DC'
_theme_fzf_colors+=' --color=marker:#B4BEFE,fg+:#CDD6F4,prompt:#CBA6F7,hl+:#F38BA8'
_theme_fzf_colors+=' --color=selected-bg:#45475A'
[[ $FZF_DEFAULT_OPTS == *"$_theme_fzf_colors"* ]] ||
  export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:+$FZF_DEFAULT_OPTS }$_theme_fzf_colors"
unset _theme_fzf_colors
