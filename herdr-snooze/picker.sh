#!/usr/bin/env bash
# picker.sh — fzf popup to pick how long to snooze the current Space.
# Opened by the `jeordin.snooze.snooze-picker` action.
#
# The list is a shortcut, not a menu: anything you type that fzf does not
# match is taken as the duration itself, so "1m", "90m" or "thu 9am" work
# without being on it. That is why this has no NORMAL mode like
# herdr-agent-picker: typing has to work from the first keystroke.
#
# j/k still move, with no mode switch, because no valid entry contains either
# letter: units are m/h/d/w, clock times am/pm, days "tomorrow" and mon..sun
# (spelled out too: "wednesday", "thursday"). If the parser ever learns a word
# with a j or k in it, this binding has to go. Arrows and ctrl-n/ctrl-p also
# move; Esc aborts.
set -euo pipefail

# Popups may launch with a minimal env; make sure the tools are findable.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Exported for the header preview below, which fzf runs in its own shell on
# every keystroke and so cannot see this script's variables.
export SNOOZE_PY="$here/snooze.py"
export SNOOZE_HELP='45m · 2h · 3d · 1w · 9am · thu 9am'

# Handed over by cmd_open_picker: a popup is a session singleton with no
# workspace context of its own, so it cannot work these out for itself.
ws="${HERDR_SNOOZE_WS:-}"
label="${HERDR_SNOOZE_LABEL:-this Space}"
current="${HERDR_SNOOZE_CURRENT:-}"   # non-empty when already snoozed

# A bad entry reopens the picker rather than closing it. Typing a stray key
# used to end the popup on a Python traceback, which meant starting over.
retry() {
  printf '\033[1;38;2;255;93;98m%s\033[0m\n' "$1"
  printf '\033[38;2;114;113;105mpress any key to try again\033[0m'
  read -r -n1 _
}

while true; do

# fzf exits non-zero when the query matches nothing, but --print-query still
# emits the query, which is exactly the free-form case. Esc gives an empty
# query and no selection, which is how abort is told apart from it.
#
# Colours are the herdr theme tokens from config.toml, so the popup's chrome
# stays neutral like the rest of herdr instead of fzf's blue prompt and pink
# pointer: text #EDEDED, subtext0 #909090, overlay0 #5A5A5A, surface1
# #262626, selection_bg #2E2E2E, accent #E8E8E8. The rows keep their own
# ANSI colours from `snooze.py rows`.
#
# Rows are spec<TAB>spec<TAB>time. --with-nth=2.. hides the raw spec and
# --nth=1 searches only the spec column of what is shown; --tabstop=1 turns
# the tab between the two display columns into a single space.
out=$(
  python3 "$SNOOZE_PY" rows "$current" \
    | fzf --ansi --print-query --exact \
          --delimiter='\t' --with-nth=2.. --nth=1 --tabstop=1 \
          --height=100% --layout=reverse --info=inline-right --no-separator \
          --prompt="${current:+[asleep, $current left] }snooze $label for " \
          --ghost="$SNOOZE_HELP" \
          --bind='start,change,focus:transform-header(python3 "$SNOOZE_PY" when {q} {1})' \
          --pointer='▸' --gutter=' ' \
          --color='fg:#909090,fg+:#EDEDED,bg+:#2E2E2E,hl:#EDEDED:bold,hl+:#EDEDED:bold' \
          --color='prompt:#909090,query:#EDEDED:bold,pointer:#E8E8E8,info:#5A5A5A' \
          --color='header:#5A5A5A,ghost:#5A5A5A,border:#262626,scrollbar:#262626' \
          --bind='esc:abort' \
          --bind='j:down,k:up' \
          --no-mouse
) || true

query=$(printf '%s\n' "$out" | sed -n 1p)
choice=$(printf '%s\n' "$out" | sed -n 2p | cut -f1)

# What you typed wins whenever it is already a valid duration. Otherwise a
# list match would hijack it: "1m" still matches the "15m" row on a substring
# search, and silently snoozing for 15 minutes when 1 was asked for is worse
# than ignoring the list.
sel="$choice"
if [ -n "$query" ] && python3 "$here/snooze.py" check "$query" 2>/dev/null; then
  sel="$query"
fi
sel="${sel:-$query}"
[ -n "$sel" ] || exit 0

# Waking is its own command, not a duration. Without this branch "wake" falls
# through to the duration parser and dies there.
if [ "$sel" = "wake" ]; then
  if ! out=$(python3 "$here/snooze.py" wake ${ws:+"$ws"} 2>&1); then
    retry "$out"; continue
  fi
  exit 0
fi

if ! out=$(python3 "$here/snooze.py" snooze "$sel" ${ws:+"$ws"} 2>&1); then
  retry "$out"; continue
fi
exit 0

done
