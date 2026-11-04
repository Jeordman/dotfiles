#!/usr/bin/env bash
# Shared by worktree-status.sh and remove-worktrees.sh. Kept bash 3.2-compatible for macOS.

find_repos() {
  find "$1" -mindepth 2 -maxdepth 3 \
    \( -name node_modules -o -path '*/.claude/worktrees' \) -prune \
    -o -type d -name .git -prune -print 2>/dev/null | sed 's#/\.git$##' | sort
}

# Prints "admin_dir<TAB>worktree_path" for each worktree of the repo that lives in a .claude/worktrees folder.
claude_worktrees() {
  local repo="$1" admin wt
  for admin in "$repo"/.git/worktrees/*; do
    [ -f "$admin/gitdir" ] || continue
    wt="$(dirname "$(cat "$admin/gitdir")")"
    case "$wt" in */.claude/worktrees/*) printf '%s\t%s\n' "$admin" "$wt" ;; esac
  done
}

process_cwds() {
  lsof -a -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | sort -u
}

# Prints "STATUS<TAB>reason". STATUS is REMOVE, KEEP or STALE.
classify_worktree() {
  local admin="$1" wt="$2" cwds_file="$3" changes
  if [ -f "$admin/locked" ]; then printf 'KEEP\tlocked\n'; return; fi
  if [ ! -d "$wt" ]; then printf 'STALE\tfolder already gone\n'; return; fi
  if ! changes="$(git -C "$wt" status --porcelain 2>/dev/null)"; then printf 'KEEP\tgit could not read it\n'; return; fi
  if [ -n "$changes" ]; then printf 'KEEP\tuncommitted changes\n'; return; fi
  if [ -n "$(git -C "$wt" log --oneline HEAD --not --remotes 2>/dev/null | head -1)" ]; then
    printf 'KEEP\tunpushed commits\n'; return
  fi
  if awk -v wt="$wt" '$0 == wt || index($0, wt "/") == 1 { found = 1 } END { exit !found }' "$cwds_file"; then
    printf 'KEEP\ta process is running inside it\n'; return
  fi
  printf 'REMOVE\t\n'
}

branch_of() {
  git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '?'
}

size_kb() {
  du -sk "$1" 2>/dev/null | cut -f1
}

node_modules_kb() {
  find "$1" -type d -name node_modules -prune -exec du -sk {} + 2>/dev/null \
    | awk '{ total += $1 } END { print total + 0 }'
}

human_size() {
  awk -v kb="$1" 'BEGIN {
    if (kb >= 1048576) printf "%.1fG", kb / 1048576
    else if (kb >= 1024) printf "%.0fM", kb / 1024
    else printf "%dK", kb
  }'
}

require_lsof() {
  command -v lsof >/dev/null 2>&1 && return
  echo "lsof is not installed, so running processes can't be checked. Nothing was touched." >&2
  exit 1
}
