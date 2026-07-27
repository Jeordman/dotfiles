#!/usr/bin/env bash
# PreToolUse Bash — targeted git guard for UNATTENDED runs.
#
# Wired only from settings.unattended.json, so it never affects normal sessions.
#
# An unattended loop must commit and push its own work, so the repo's blanket
# "AI never runs git state ops" deny cannot apply. This replaces it with a
# narrower rule: writing to a feature branch is fine, but nothing may reach a
# protected branch, rewrite history, or move HEAD out from under the loop.
#
# Why a hook and not just permission patterns: the dangerous cases can't be
# matched textually. `git push` with no args pushes the *upstream* branch, and
# `git push origin HEAD` names no branch at all — both need resolution against
# real repo state to know whether the target is protected.

set -uo pipefail

PROTECTED_RE='^(master|main|staging|production|release|develop)$'

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$CMD" ] || exit 0

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# Strip a leading `cd <path> &&` so the git call is at the front.
TRIMMED=$(printf '%s' "$CMD" \
  | sed -E 's/^[[:space:]]+//; s/^cd[[:space:]]+[^[:space:]]+[[:space:]]*&&[[:space:]]*//')

# Subshell bypass first: `bash -c "git push origin master"` starts with `bash`,
# so it would slip past the git-prefix gate below. Scan the raw string for the
# cases that must never happen regardless of how they are wrapped. Narrowed to
# shell invocations carrying -c, so a literal mention in `echo` or `grep` is not
# a false positive.
case "$TRIMMED" in
  bash|sh|zsh|bash\ *|sh\ *|zsh\ *)
    if printf '%s' "$CMD" | grep -qE '[[:space:]]-[a-zA-Z]*c[a-zA-Z]*([[:space:]]|=)'; then
      if printf '%s' "$CMD" | grep -qE "git[[:space:]]+push[^\"']*(master|main|staging|production|release|develop)([[:space:]\"']|$)"; then
        deny "unattended: refusing to push to a protected branch via a subshell."
      fi
      if printf '%s' "$CMD" | grep -qE "git[[:space:]]+push[^\"']*(--force|--force-with-lease|-f)([[:space:]\"']|$)"; then
        deny "unattended: refusing to force-push via a subshell."
      fi
      if printf '%s' "$CMD" | grep -qE "git[[:space:]]+(reset|rebase|filter-branch|clean|checkout|switch)([[:space:]\"']|$)"; then
        deny "unattended: refusing history rewrites or HEAD movement via a subshell."
      fi
    fi
    ;;
esac

case "$TRIMMED" in
  git|git\ *) ;;
  *) exit 0 ;;
esac

# Resolve the subcommand, walking past git global options that take an argument.
SUB=$(printf '%s' "$TRIMMED" | awk '
  function takes_arg(t) {
    return (t=="-C"||t=="-c"||t=="--git-dir"||t=="--work-tree"||t=="--namespace"||
            t=="--super-prefix"||t=="--exec-path"||t=="--config-env"||t=="--attr-source")
  }
  { if ($1!="git") exit
    i=2
    while (i<=NF) {
      t=$i
      if (substr(t,1,1)!="-") { print t; exit }
      if (takes_arg(t)) { i+=2; continue }
      i++
    } }')
[ -n "$SUB" ] || exit 0

case "$SUB" in
  # History rewrites and index/worktree resets: never, in any mode. The loop's
  # own commits are its audit trail, and a reset can silently discard a verified
  # row's work.
  reset|rebase|filter-branch|am)
    deny "unattended: git $SUB is never allowed — it rewrites history the ledger depends on. Make a forward commit instead."
    ;;
  # Moving HEAD mid-loop desynchronises the working tree from the ledger.
  checkout|switch)
    deny "unattended: git $SUB is not allowed inside the loop — the branch is fixed for the run. deploy-watch owns checkout, before the session starts."
    ;;
  clean)
    deny "unattended: git clean is not allowed — it can delete untracked evidence (test output, screenshots) the verifier needs."
    ;;
  remote)
    # Read-only forms are fine; mutating the remote set is not.
    if printf '%s' "$TRIMMED" | grep -qE '\bremote[[:space:]]+(add|remove|rm|rename|set-url|set-head|set-branches|prune|update)\b'; then
      deny "unattended: modifying git remotes is not allowed."
    fi
    exit 0
    ;;
  push)
    # Force in any spelling.
    if printf '%s' "$TRIMMED" | grep -qE '(^|[[:space:]])(--force|--force-with-lease|--force-if-includes|-f)([[:space:]=]|$)'; then
      deny "unattended: force-push is never allowed."
    fi
    # A leading '+' in a refspec is a force push.
    if printf '%s' "$TRIMMED" | grep -qE '[[:space:]]\+[^[:space:]]*:'; then
      deny "unattended: force-push via '+refspec' is never allowed."
    fi
    if printf '%s' "$TRIMMED" | grep -qE '(^|[[:space:]])(--mirror|--all|--delete|--tags)([[:space:]]|$)'; then
      deny "unattended: bulk or destructive push flags (--mirror/--all/--delete/--tags) are not allowed."
    fi

    # Resolve the destination branch. Prefer an explicit refspec; the last
    # colon-separated component is the remote ref. Otherwise fall back to the
    # branch actually checked out, which is what a bare `git push` sends.
    DEST=$(printf '%s' "$TRIMMED" | awk '
      { for (i=2; i<=NF; i++) {
          t=$i
          if (substr(t,1,1)=="-") continue
          if (t=="push"||t=="git") continue
          last=t
        }
        if (last ~ /:/) { n=split(last,parts,":"); print parts[n] }
        else if (last!="" && last!="origin" && last!="HEAD") { print last }
      }')
    if [ -z "$DEST" ] || [ "$DEST" = "HEAD" ]; then
      DEST=$(git branch --show-current 2>/dev/null)
    fi
    DEST=${DEST#refs/heads/}

    if printf '%s' "$DEST" | grep -qE "$PROTECTED_RE"; then
      deny "unattended: refusing to push to protected branch '$DEST'. The loop only ever pushes its own feature branch; a human opens and merges the PR."
    fi
    # Unresolvable destination is treated as unsafe rather than assumed fine.
    if [ -z "$DEST" ]; then
      deny "unattended: could not resolve the push destination, so it cannot be checked against the protected list. Push an explicit branch, e.g. 'git push origin <branch>'."
    fi
    exit 0
    ;;
  # add / commit / fetch / status / diff / log / show / ls-remote / branch: allowed.
  *) ;;
esac

exit 0
