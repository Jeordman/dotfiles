#!/usr/bin/env bash
# Read-only: never runs `git worktree` and never deletes anything.
set -u
. "$(dirname "$0")/worktrees-lib.sh"

root="${1:-$HOME/unicity}"
[ -d "$root" ] || { echo "Folder not found: $root" >&2; exit 1; }
require_lsof

cwds_file="$(mktemp)"
trap 'rm -f "$cwds_file"' EXIT
process_cwds > "$cwds_file"

removable=0 kept=0 stale=0 total_kb=0 total_nm_kb=0
echo "ROOT $root"
while read -r repo; do
  entries="$(claude_worktrees "$repo")"
  [ -n "$entries" ] || continue
  echo "REPO ${repo#"$root"/}"
  while IFS="$(printf '\t')" read -r admin wt; do
    name="${wt##*/}"
    IFS="$(printf '\t')" read -r status reason <<< "$(classify_worktree "$admin" "$wt" "$cwds_file")"
    case "$status" in
      REMOVE)
        kb="$(size_kb "$wt")"; nm_kb="$(node_modules_kb "$wt")"
        removable=$((removable + 1)); total_kb=$((total_kb + kb)); total_nm_kb=$((total_nm_kb + nm_kb))
        echo "  REMOVE $name [$(branch_of "$wt")] $(human_size "$kb") total, $(human_size $((kb - nm_kb))) excluding node_modules" ;;
      STALE)
        stale=$((stale + 1)); echo "  STALE  $name ($reason)" ;;
      *)
        kept=$((kept + 1)); echo "  KEEP   $name [$(branch_of "$wt")] ($reason)" ;;
    esac
  done <<< "$entries"
done < <(find_repos "$root")

echo "SUMMARY removable=$removable kept=$kept stale=$stale size=$(human_size "$total_kb") excluding_node_modules=$(human_size $((total_kb - total_nm_kb)))"
