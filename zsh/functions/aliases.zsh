# aliases.zsh — make eza, ripgrep and fd print OSC 8 hyperlinks, so kitty can
# open what they list (see docs/kitty-links.md). Source from ~/.zshrc; nothing
# else in the repo depends on it.

alias ls='eza --icons auto --hyperlink'
alias rg='rg --hyperlink-format=kitty'
alias fd='fd --hyperlink'
