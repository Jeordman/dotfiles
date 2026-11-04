#!/usr/bin/env bash
# Run by the user, not by Claude. Re-checks every worktree right before removing it.
set -u
. "$(dirname "$0")/worktrees-lib.sh"

root="${1:-$HOME/unicity}"
[ -d "$root" ] || { echo "Folder not found: $root" >&2; exit 1; }
require_lsof

cwds_file="$(mktemp)"
trap 'rm -f "$cwds_file"' EXIT
process_cwds > "$cwds_file"

removed=0 skipped=0 failed=0 freed_kb=0
while read -r repo; do
  entries="$(claude_worktrees "$repo")"
  [ -n "$entries" ] || continue
  repo_name="${repo#"$root"/}"
  has_stale=false
  while IFS="$(printf '\t')" read -r admin wt; do
    name="${wt##*/}"
    IFS="$(printf '\t')" read -r status reason <<< "$(classify_worktree "$admin" "$wt" "$cwds_file")"
    case "$status" in
      REMOVE)
        kb="$(size_kb "$wt")"
        if git -C "$repo" worktree remove "$wt"; then
          removed=$((removed + 1)); freed_kb=$((freed_kb + kb)); echo "REMOVED $repo_name/$name ($(human_size "$kb"))"
        else
          failed=$((failed + 1)); echo "FAILED  $repo_name/$name"
        fi ;;
      STALE) has_stale=true ;;
      *) skipped=$((skipped + 1)); echo "SKIPPED $repo_name/$name ($reason)" ;;
    esac
  done <<< "$entries"
  if [ "$has_stale" = true ]; then
    git -C "$repo" worktree prune -v 2>&1 | sed "s#^#PRUNED  $repo_name: #"
  fi
done < <(find_repos "$root")

echo "SUMMARY removed=$removed skipped=$skipped failed=$failed freed_up_to=$(human_size "$freed_kb")"
[ "$failed" -eq 0 ]
