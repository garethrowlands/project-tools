# sw — pick a worktree or branch of the current repo; cd to worktrees, git switch to plain branches
# (or, with ctrl-o, check a plain branch out in a new sibling worktree and cd there).

# Path of the main worktree, or empty outside a repo.
_sw_root() {
  git worktree list --porcelain 2>/dev/null | awk 'NR == 1 { print substr($0, 10); exit }'
}

# Sibling worktree path for a branch: <root>-<branch>, minus any leading
# prefix segment (feat/, fix/, ...) and with remaining slashes as dashes.
_sw_worktree_path() {
  local root=$1 slug=${2#*/}
  print -r -- "${root:h}/${root:t}-${slug//\//-}"
}

# Outputs PATH<TAB>BRANCH<TAB>DISPLAY lines: worktrees first, then branches
# without one (PATH empty), each group most-recently-committed first.
_sw_list() {
  local root=$(_sw_root)
  [[ -n $root ]] || { print -u2 "sw: not in a git repository"; return 1 }
  {
    git for-each-ref --sort=-committerdate refs/heads \
      --format='%(worktreepath)%09%(refname:short)%09%(HEAD)'
    git worktree list --porcelain | awk '
      /^worktree / { p = substr($0, 10) }
      /^detached/  { print p "\t(detached)\t " }'
  } | awk -F'\t' -v root="$root" -v home="$HOME" '
    function short(p) {
      if (p == "")   return ""
      if (p == root) return "(main worktree)"
      if (substr(p, 1, length(root) + 1) == root "/") return substr(p, length(root) + 2)
      parent = root; sub(/\/[^\/]*$/, "", parent)
      if (substr(p, 1, length(parent) + 1) == parent "/") return ".." substr(p, length(parent) + 1)
      if (substr(p, 1, length(home) + 1) == home "/") return "~" substr(p, length(home) + 1)
      return p
    }
    {
      n++; path[n] = $1; br[n] = $2; cur[n] = ($3 == "*" ? "*" : " ")
      if (length($2) > w) w = length($2)
    }
    END {
      for (pass = 1; pass <= 2; pass++)
        for (i = 1; i <= n; i++) {
          if ((pass == 1) != (path[i] != "")) continue
          printf "%s\t%s\t%s %s %-*s  \033[2m%s\033[0m\n", path[i], br[i], cur[i],
            (path[i] != "" ? "⎇" : " "), w, br[i], short(path[i])
        }
    }'
}

sw() {
  local out key line dir branch
  out=$(_sw_list | fzf --ansi --height 40% --reverse --delimiter=$'\t' --with-nth=3 \
    --expect=ctrl-o --header='enter: switch here · ctrl-o: new worktree') || return
  # --expect puts the key pressed (empty for enter) on the first line.
  key=${out%%$'\n'*}
  line=${out#*$'\n'}
  dir=${line%%$'\t'*}
  branch=${${line#*$'\t'}%%$'\t'*}
  if [[ -n $dir ]]; then
    cd "$dir"
  elif [[ $key == ctrl-o ]]; then
    dir=$(_sw_worktree_path "$(_sw_root)" "$branch")
    [[ -e $dir ]] && { print -u2 "sw: $dir already exists"; return 1 }
    git worktree add "$dir" "$branch" && cd "$dir"
  else
    git switch "$branch"
  fi
}
