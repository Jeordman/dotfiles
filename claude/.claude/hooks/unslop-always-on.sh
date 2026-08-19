#!/usr/bin/env sh
# SessionStart hook: injects the vendored unslop ruleset into every session when
# the user has opted in by creating $CLAUDE_CONFIG_DIR/.unslop-always.
#
# Why this exists: unslop's frontmatter says "Must always apply", but that is only
# prose in a description field. Claude Code decides per request whether to load a
# skill, so plain questions ("what is this repo for?") never read as "load the
# writing skill" and unslop silently never fires. Injecting the body at session
# start is what makes the always-apply claim actually true.
#
# The skill file itself is vendored upstream (vendor/cursor-plugins, a submodule),
# so it is never edited locally. This hook reads it at runtime, which keeps
# upstream as the single source of truth and lets `git pull` update the rules.
# Local additions go in the preamble below, not in the vendored file.
#
# Never blocks session start: any failure exits 0. Pure POSIX sh so it runs
# wherever Claude Code runs a command hook, with no dependency on Node or bash.

claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
flag_path="$claude_dir/.unslop-always"

# Only fire when the user has opted in.
[ -f "$flag_path" ] || exit 0

# Resolve SKILL.md relative to this script rather than trusting an exported env
# var, so the hook keeps working through the stow symlink and on any machine.
# skills/unslop is itself a symlink into vendor/cursor-plugins/pstack/skills.
script_dir=$(dirname -- "$0")
skill_path="$script_dir/../skills/unslop/SKILL.md"
[ -f "$skill_path" ] || exit 0

# Strip a leading YAML frontmatter block (--- ... --- at the very top of file).
body=$(awk '
  NR == 1 && $0 ~ /^---[[:space:]]*$/ { in_fm = 1; next }
  in_fm && $0 ~ /^---[[:space:]]*$/   { in_fm = 0; next }
  !in_fm                              { print }
' "$skill_path") || exit 0

printf 'UNSLOP ACTIVE (always-on). The ruleset below applies to every response for the rest of the session, not only to files being edited. It does not expire after a few turns and does not lapse when the topic changes; if unsure whether it still applies, it does. "stop unslop" turns it off for this session; delete %s to turn always-on off for good.\n\nOne addition, since unslop does not cover it: prefer bullet points and short lists over paragraphs when content is genuinely list-shaped. This does not override item 16, which still applies to the bold-label-and-colon pattern within a line.\n\n%s\n' \
  "$flag_path" "$body"
