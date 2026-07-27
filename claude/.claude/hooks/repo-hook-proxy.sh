#!/usr/bin/env bash
# repo-hook-proxy.sh — run a repo-owned hook script from a user-scope wiring.
#
# Usage (from settings.unattended.json):
#   bash ~/.claude/hooks/repo-hook-proxy.sh post-edit-format.sh
#
# Why this exists. The unattended profile deliberately omits the `project`
# settings scope, which is what lets the loop run at all — but that also drops
# the repo's *useful* hooks along with its blocking ones (post-edit formatting,
# the tsc gate, the store-policy guard). Re-declaring them in the profile by
# absolute path would hardcode one worktree; this resolves the repo root at call
# time instead, so the same wiring works in every gtr worktree.
#
# The logic stays in the repo, maintained by the team. Only the wiring is
# personal.
#
# Stdin is passed through untouched, and the child's stdout and exit code are
# propagated, so the proxy is transparent to Claude Code's hook protocol.
#
# A missing target is reported on stderr rather than silently succeeding: if a
# teammate renames a hook, an unattended run would otherwise quietly lose
# formatting or a gate with no signal at all.

set -uo pipefail

HOOK_NAME="${1:-}"
if [ -z "$HOOK_NAME" ]; then
  echo "repo-hook-proxy: no hook name given" >&2
  exit 0        # never block the turn on a wiring mistake
fi

INPUT=$(cat)

ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$ROOT" ]; then
  # Not in a repo (or a bare context) — nothing to proxy to.
  exit 0
fi

TARGET="$ROOT/.claude/hooks/$HOOK_NAME"
if [ ! -f "$TARGET" ]; then
  echo "repo-hook-proxy: $HOOK_NAME not found at $TARGET — skipping. If it was renamed or removed upstream, update the wiring in settings.unattended.json." >&2
  exit 0
fi

printf '%s' "$INPUT" | bash "$TARGET"
exit $?
